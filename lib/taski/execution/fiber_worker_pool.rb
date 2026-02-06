# frozen_string_literal: true

require "etc"

module Taski
  module Execution
    # FiberWorkerPool manages N threads, each with its own command Queue.
    # Tasks are executed within Fibers on worker threads.
    # When a Fiber yields [:need_dep, dep_class, method], the worker
    # resolves the dependency via SharedState:
    #
    # - :completed → resume Fiber immediately with the value
    # - :wait → park the Fiber (it will be resumed later via the thread's queue)
    # - :start → start the dependency as a nested Fiber on the same thread
    #
    # Worker threads process three kinds of commands:
    # - [:execute, task_class, wrapper] → create and drive a new Fiber
    # - [:resume, fiber, value]         → resume a parked Fiber with a value
    # - [:resume_error, fiber, error]   → resume a parked Fiber with an error
    # - :shutdown                       → exit the worker loop
    class FiberWorkerPool
      attr_reader :worker_count

      # @param shared_state [SharedState] Centralized state for coordination
      # @param registry [Registry] Task registry
      # @param execution_context [ExecutionContext] For observer notifications
      # @param worker_count [Integer, nil] Number of worker threads
      # @param completion_queue [Queue] Queue for completion events back to executor
      def initialize(shared_state:, registry:, execution_context:, completion_queue:, worker_count: nil)
        @shared_state = shared_state
        @registry = registry
        @execution_context = execution_context
        @worker_count = worker_count || default_worker_count
        @completion_queue = completion_queue
        @threads = []
        @thread_queues = []
        @next_thread_index = 0
        @fiber_contexts_mutex = Mutex.new
        @fiber_contexts = {}
      end

      # Start all worker threads.
      def start
        @worker_count.times do
          queue = Queue.new
          @thread_queues << queue
          thread = Thread.new(queue) { |q| worker_loop(q) }
          @threads << thread
          @registry.register_thread(thread)
        end
      end

      # Enqueue a task for execution on a worker thread.
      # Round-robins across worker threads.
      # @param task_class [Class] The task class to execute
      # @param wrapper [TaskWrapper] The task wrapper
      def enqueue(task_class, wrapper)
        queue = @thread_queues[@next_thread_index % @worker_count]
        @next_thread_index += 1
        queue.push([:execute, task_class, wrapper])
        debug_log("Enqueued #{task_class} on thread #{(@next_thread_index - 1) % @worker_count}")
      end

      # Shutdown all worker threads gracefully.
      def shutdown
        @thread_queues.each { |q| q.push(:shutdown) }
        @threads.each(&:join)
      end

      private

      def default_worker_count
        Etc.nprocessors.clamp(2, 8)
      end

      def worker_loop(queue)
        loop do
          cmd = queue.pop
          break if cmd == :shutdown

          case cmd[0]
          when :execute
            _, task_class, wrapper = cmd
            drive_fiber(task_class, wrapper, queue)
          when :resume
            _, fiber, value = cmd
            resume_fiber(fiber, value, queue)
          when :resume_error
            _, fiber, error = cmd
            resume_fiber_with_error(fiber, error, queue)
          end
        end
      end

      # Create and drive a Fiber that runs the task.
      def drive_fiber(task_class, wrapper, queue)
        return if @registry.abort_requested?

        fiber = Fiber.new do
          setup_fiber_context
          wrapper.task.run
        end

        unless wrapper.mark_running
          # Already running or completed elsewhere
          wrapper.wait_for_completion
          @shared_state.mark_completed(task_class)
          @completion_queue.push({task_class: task_class, wrapper: wrapper})
          return
        end

        @execution_context.notify_task_registered(task_class)
        @execution_context.notify_task_started(task_class)

        start_output_capture(task_class)
        run_fiber_loop(fiber, task_class, wrapper, queue)
      end

      # Drive a Fiber forward, handling yields and completion.
      def run_fiber_loop(fiber, task_class, wrapper, queue)
        result = fiber.resume

        while fiber.alive?
          if result.is_a?(Array) && result[0] == :need_dep
            _, dep_class, method = result
            handle_dependency(dep_class, method, fiber, task_class, wrapper, queue)
            return # Fiber is either continuing or parked
          else
            # Unknown yield - treat as completion
            break
          end
        end

        # Fiber completed normally
        complete_task(task_class, wrapper, result)
      rescue => e
        fail_task(task_class, wrapper, e)
      end

      # Handle a dependency request from a Fiber.
      def handle_dependency(dep_class, method, fiber, task_class, wrapper, queue)
        status = @shared_state.request_dependency(dep_class, method, queue, fiber)

        case status[0]
        when :completed
          # Resume immediately
          value = status[1]
          continue_fiber(fiber, value, task_class, wrapper, queue)
        when :error
          # Dependency failed
          error = status[1]
          continue_fiber_with_error(fiber, error, task_class, wrapper, queue)
        when :wait
          # Fiber is parked. Store context for when it's resumed.
          store_fiber_context(fiber, task_class, wrapper)
        when :start
          # Need to start the dependency - store waiting fiber context first
          store_fiber_context(fiber, task_class, wrapper)
          start_dependency(dep_class, queue)
        end
      end

      # Continue a fiber after a dependency resolves synchronously.
      def continue_fiber(fiber, value, task_class, wrapper, queue)
        result = fiber.resume(value)

        while fiber.alive?
          if result.is_a?(Array) && result[0] == :need_dep
            _, dep_class, method = result
            handle_dependency(dep_class, method, fiber, task_class, wrapper, queue)
            return
          else
            break
          end
        end

        complete_task(task_class, wrapper, result)
      rescue => e
        fail_task(task_class, wrapper, e)
      end

      # Continue a fiber with an error (dependency failed).
      def continue_fiber_with_error(fiber, error, task_class, wrapper, queue)
        result = fiber.resume([:_taski_error, error])

        while fiber.alive?
          if result.is_a?(Array) && result[0] == :need_dep
            _, dep_class, method = result
            handle_dependency(dep_class, method, fiber, task_class, wrapper, queue)
            return
          else
            break
          end
        end

        complete_task(task_class, wrapper, result)
      rescue => e
        fail_task(task_class, wrapper, e)
      end

      # Resume a parked Fiber from the thread queue.
      def resume_fiber(fiber, value, queue)
        context = get_fiber_context(fiber)
        return unless context

        task_class, wrapper = context
        continue_fiber(fiber, value, task_class, wrapper, queue)
      end

      # Resume a parked Fiber with an error.
      def resume_fiber_with_error(fiber, error, queue)
        context = get_fiber_context(fiber)
        return unless context

        task_class, wrapper = context
        continue_fiber_with_error(fiber, error, task_class, wrapper, queue)
      end

      # Start a dependency task as a new Fiber on this thread.
      def start_dependency(dep_class, queue)
        dep_wrapper = get_or_create_wrapper(dep_class)
        @shared_state.register(dep_class, dep_wrapper)
        drive_fiber(dep_class, dep_wrapper, queue)
      end

      def complete_task(task_class, wrapper, result)
        stop_output_capture
        wrapper.mark_completed(result)
        @shared_state.mark_completed(task_class)
        @completion_queue.push({task_class: task_class, wrapper: wrapper})
        teardown_fiber_context
      end

      def fail_task(task_class, wrapper, error)
        stop_output_capture
        wrapper.mark_failed(error)
        @shared_state.mark_failed(task_class, error)
        @completion_queue.push({task_class: task_class, wrapper: wrapper, error: error})
        teardown_fiber_context
      end

      def setup_fiber_context
        Thread.current[:taski_fiber_context] = true
        ExecutionContext.current = @execution_context
        Taski.set_current_registry(@registry)
      end

      def teardown_fiber_context
        Thread.current[:taski_fiber_context] = nil
        ExecutionContext.current = nil
        Taski.clear_current_registry
      end

      def start_output_capture(task_class)
        output_capture = @execution_context.output_capture
        output_capture&.start_capture(task_class)
      end

      def stop_output_capture
        output_capture = @execution_context.output_capture
        output_capture&.stop_capture
      end

      def store_fiber_context(fiber, task_class, wrapper)
        @fiber_contexts_mutex.synchronize do
          @fiber_contexts[fiber.object_id] = [task_class, wrapper]
        end
      end

      def get_fiber_context(fiber)
        @fiber_contexts_mutex.synchronize do
          @fiber_contexts.delete(fiber.object_id)
        end
      end

      def get_or_create_wrapper(task_class)
        @registry.get_or_create(task_class) do
          task_instance = task_class.allocate
          task_instance.send(:initialize)
          TaskWrapper.new(task_instance, registry: @registry, execution_context: @execution_context)
        end
      end

      def debug_log(message)
        return unless ENV["TASKI_DEBUG"]
        puts "[FiberWorkerPool] #{message}"
      end
    end
  end
end
