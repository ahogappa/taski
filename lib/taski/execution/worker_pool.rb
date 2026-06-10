# frozen_string_literal: true

require "etc"

module Taski
  module Execution
    def self.default_worker_count
      Etc.nprocessors.clamp(2, 8)
    end

    # WorkerPool manages N threads, each with its own command Queue.
    # Tasks are executed within Fibers on worker threads.
    #
    # Fiber protocol supports two yield types (FiberProtocol Data classes):
    # - StartDep(task_class)          → non-blocking. Starts dep on another
    #   thread and resumes the Fiber immediately. Used for speculative prestart.
    # - NeedDep(task_class, method)   → blocking. Resolves dependency via
    #   TaskWrapper#request_value, which returns one of:
    #   - DepCompleted(value) → resume Fiber immediately with the value
    #   - DepFailed(error)    → resume the Fiber with a DepError to propagate
    #   - DepWaiting          → park the Fiber (resumed later via the thread's queue)
    #   - DepStarting         → start the dependency as a nested Fiber on this thread
    #
    # Worker threads process these commands (FiberProtocol Data classes):
    # - Execute(task_class, wrapper)       → create and drive a new Fiber
    # - ExecuteClean(task_class, wrapper)  → run clean directly (no Fiber)
    # - Resume(fiber, value)               → resume a parked Fiber with a value
    # - ResumeError(fiber, error)          → resume a parked Fiber with an error
    # - :shutdown                          → exit the worker loop
    class WorkerPool
      attr_reader :worker_count

      def initialize(registry:, execution_facade:, completion_queue:, worker_count: nil)
        @registry = registry
        @execution_facade = execution_facade
        @worker_count = worker_count || Execution.default_worker_count
        @completion_queue = completion_queue
        # Capture the calling execution's args/env now (on the caller fiber, where
        # they are in scope) so each worker can re-establish them — fiber-local
        # storage does not cross the caller -> worker thread boundary.
        @run_args = Taski.args
        @run_env = Taski.env
        @threads = []
        @thread_queues = []
        @next_thread_index = 0
        @fiber_contexts_mutex = Mutex.new
        @fiber_contexts = {}
        @task_start_times_mutex = Mutex.new
        @task_start_times = {}
        @enqueue_mutex = Mutex.new
      end

      def start
        @worker_count.times do
          queue = Queue.new
          @thread_queues << queue
          thread = Thread.new(queue) { |q| worker_loop(q) }
          @threads << thread
          @registry.register_thread(thread)
        end
      end

      # Round-robins across worker threads.
      def enqueue(task_class, wrapper)
        @enqueue_mutex.synchronize do
          queue = @thread_queues[@next_thread_index % @worker_count]
          @next_thread_index += 1
          queue.push(FiberProtocol::Execute.new(task_class, wrapper))
          Taski::Logging.debug(Taski::Logging::Events::WORKER_POOL_ENQUEUED, task: task_class.name, thread_index: (@next_thread_index - 1) % @worker_count)
        end
      end

      # Clean tasks run directly without Fiber wrapping.
      def enqueue_clean(task_class, wrapper)
        @enqueue_mutex.synchronize do
          queue = @thread_queues[@next_thread_index % @worker_count]
          @next_thread_index += 1
          queue.push(FiberProtocol::ExecuteClean.new(task_class, wrapper))
        end
      end

      def shutdown
        @thread_queues.each { |q| q.push(:shutdown) }
        @threads.each(&:join)
      end

      private

      def worker_loop(queue)
        loop do
          cmd = queue.pop
          break if cmd == :shutdown

          case cmd
          in FiberProtocol::Execute => exec
            drive_fiber(exec.task_class, exec.wrapper, queue)
          in FiberProtocol::Resume => res
            resume_fiber(res.fiber, res.value, queue)
          in FiberProtocol::ResumeError => err
            resume_fiber_with_error(err.fiber, err.error, queue)
          in FiberProtocol::ExecuteClean => clean
            execute_clean_task(clean.task_class, clean.wrapper)
          else
            raise "[BUG] unexpected worker command: #{cmd.inspect}"
          end
        end
      end

      # Drive a new Fiber for a task. The caller MUST have already called
      # wrapper.mark_running before enqueueing — drive_fiber never calls it.
      def drive_fiber(task_class, wrapper, queue)
        return abort_unstarted_task(task_class, wrapper) if @registry.abort_requested?

        analysis = Taski::StaticAnalysis::StartDepAnalyzer.analyze(task_class)
        if Taski.logger
          Taski::Logging.debug(
            Taski::Logging::Events::PRESTART_PLAN,
            task: task_class.name,
            prestarted: analysis.start_deps.map(&:name),
            sync: analysis.sync_deps.map(&:name),
            stopped_at: analysis.stopped_at&.line
          )
        end
        fiber = Fiber.new do
          setup_run_thread_locals
          Thread.current[:taski_start_deps] = analysis.start_deps
          (analysis.start_deps | analysis.sync_deps).each { |dep_class| Fiber.yield(FiberProtocol::StartDep.new(dep_class)) }
          run_result = wrapper.task.run
          resolve_proxy_exports(wrapper)
          run_result
        ensure
          Thread.current[:taski_start_deps] = nil
        end

        now = Time.now
        @task_start_times_mutex.synchronize { @task_start_times[task_class] = now }
        Taski::Logging.info(Taski::Logging::Events::TASK_STARTED, task: task_class.name)
        @execution_facade.notify_task_updated(task_class, previous_state: :pending, current_state: :running, phase: :run, timestamp: now)

        start_output_capture(task_class)
        drive_fiber_loop(fiber, task_class, wrapper, queue)
      rescue => e
        # An exception escaping the pre-fiber setup (analysis, fiber creation,
        # notifications, capture) would otherwise propagate out of worker_loop
        # and kill this worker thread, leaving tasks routed to its queue stuck
        # forever. Route it to fail_task so the task fails cleanly and the
        # worker keeps serving. (drive_fiber_loop has its own rescue, so this
        # only catches setup-phase errors and never double-fails.)
        fail_task(task_class, wrapper, e)
      end

      # Drive a Fiber forward by resuming it with resume_value.
      # fiber.resume is called INSIDE this method so that exceptions
      # are caught by the rescue and routed to fail_task.
      def drive_fiber_loop(fiber, task_class, wrapper, queue, resume_value = nil)
        result = fiber.resume(resume_value)

        while fiber.alive?
          case result
          in FiberProtocol::StartDep => start_dep
            handle_start_dep(start_dep.task_class)
            result = fiber.resume
          in FiberProtocol::NeedDep => need_dep
            case handle_dependency(need_dep.task_class, need_dep.method, fiber, task_class, wrapper, queue)
            in FiberProtocol::Parked
              return # fiber parked (or nested dep driven); resumed later via its queue
            in FiberProtocol::ResumeWith(value:)
              # Dependency was already resolved: continue iteratively rather than
              # recursing, so a task reading many completed deps cannot overflow
              # the worker stack.
              result = fiber.resume(value)
            end
          else
            break # task.run returned a non-protocol value (normal completion)
          end
        end

        complete_task(task_class, wrapper, result)
      rescue => e
        fail_task(task_class, wrapper, e)
      end

      # Resolve a dependency for a fiber that yielded NeedDep. Returns a value
      # the driver loop acts on:
      #   FiberProtocol::ResumeWith(value) → resolved; resume the fiber with value
      #   FiberProtocol::Parked            → fiber parked (or a nested dep is being
      #                                      driven); the driver loop must stop and
      #                                      let a later queue event resume the fiber.
      def handle_dependency(dep_class, method, fiber, task_class, wrapper, queue)
        dep_wrapper = @registry.create_wrapper(dep_class, execution_facade: @execution_facade)

        case dep_wrapper.request_value(method, queue, fiber)
        in FiberProtocol::DepCompleted(value:)
          FiberProtocol::ResumeWith.new(value)
        in FiberProtocol::DepFailed(error:)
          FiberProtocol::ResumeWith.new(FiberProtocol::DepError.new(error))
        in FiberProtocol::DepWaiting
          store_fiber_context(fiber, task_class, wrapper)
          FiberProtocol::Parked.new
        in FiberProtocol::DepStarting
          store_fiber_context(fiber, task_class, wrapper)
          # dep_wrapper is already RUNNING (set atomically by request_value)
          drive_fiber(dep_class, dep_wrapper, queue)
          FiberProtocol::Parked.new
        end
      end

      # Resume a parked Fiber from the thread queue.
      # Re-establishes the execution context (registry/args/env) on the worker
      # thread before resuming. A parked fiber keeps its own fiber-local state
      # across the suspend (teardown runs on completion/failure, not on park), so
      # this is what carries the execution's context onto whichever worker thread
      # picks the fiber up.
      def resume_fiber(fiber, value, queue)
        resume_fiber_with_value(fiber, value, queue)
      end

      def resume_fiber_with_error(fiber, error, queue)
        resume_fiber_with_value(fiber, FiberProtocol::DepError.new(error), queue)
      end

      def resume_fiber_with_value(fiber, resume_value, queue)
        context = get_fiber_context(fiber)
        return unless context

        task_class, wrapper = context
        setup_run_thread_locals
        start_output_capture(task_class)
        drive_fiber_loop(fiber, task_class, wrapper, queue, resume_value)
      end

      # Handle :start_dep — speculatively start a dependency on another thread.
      # Non-blocking: the calling Fiber is resumed immediately after enqueueing.
      # Uses mark_running to prevent duplicate starts.
      def handle_start_dep(dep_class)
        dep_wrapper = @registry.create_wrapper(dep_class, execution_facade: @execution_facade)
        return unless dep_wrapper.mark_running

        # Notify Executor so Scheduler can track the running state.
        # Must be pushed before the execute command to guarantee ordering.
        @completion_queue.push(FiberProtocol::StartDepNotify.new(dep_class))

        @enqueue_mutex.synchronize do
          target_queue = @thread_queues[@next_thread_index % @worker_count]
          @next_thread_index += 1
          target_queue.push(FiberProtocol::Execute.new(dep_class, dep_wrapper))
        end
      end

      # Resolve any TaskProxy instances stored in exported ivars.
      # After task.run, proxies assigned to @value etc. must be resolved
      # while still inside the Fiber context so Fiber.yield works.
      def resolve_proxy_exports(wrapper)
        wrapper.task.class.exported_methods.each do |method|
          ivar = :"@#{method}"
          val = wrapper.task.instance_variable_get(ivar)
          next unless val.respond_to?(:__taski_proxy_resolve__)
          resolved = val.__taski_proxy_resolve__
          wrapper.task.instance_variable_set(ivar, resolved)
        end
      end

      def complete_task(task_class, wrapper, result)
        stop_output_capture
        duration = task_duration_ms(task_class)
        Taski::Logging.info(Taski::Logging::Events::TASK_COMPLETED, task: task_class.name, duration_ms: duration)
        wrapper.mark_completed(result)
        @completion_queue.push(FiberProtocol::TaskCompleted.new(task_class, wrapper))
        teardown_thread_locals
      end

      def fail_task(task_class, wrapper, error)
        stop_output_capture
        @registry.request_abort! if error.is_a?(Taski::TaskAbortException)
        duration = task_duration_ms(task_class)
        Taski::Logging.error(Taski::Logging::Events::TASK_FAILED, task: task_class.name, duration_ms: duration)
        wrapper.mark_failed(error)
        @completion_queue.push(FiberProtocol::TaskFailed.new(task_class, wrapper, error))
        teardown_thread_locals
      end

      # A task that was scheduled (marked running) but never started because
      # abort was requested first. Its Fiber never ran, so no thread-locals or
      # output capture were set up. We must still mark it failed (releasing any
      # fibers parked on it) and push a terminal event so the Executor's main
      # loop does not block forever waiting on a completion that never arrives.
      def abort_unstarted_task(task_class, wrapper)
        error = Taski::TaskAbortException.new("Execution aborted before #{task_class.name} started")
        wrapper.mark_failed(error)
        @completion_queue.push(FiberProtocol::TaskFailed.new(task_class, wrapper, error))
      end

      # Execute a clean task directly (no Fiber needed).
      def execute_clean_task(task_class, wrapper)
        return abort_unstarted_clean_task(task_class, wrapper) if @registry.abort_requested?

        setup_clean_thread_locals
        start_output_capture(task_class)
        clean_start = Time.now
        @execution_facade.notify_task_updated(task_class, previous_state: :pending, current_state: :running, phase: :clean, timestamp: clean_start)
        Taski::Logging.debug(Taski::Logging::Events::TASK_CLEAN_STARTED, task: task_class.name)

        result = wrapper.task.clean
        duration = ((Time.now - clean_start) * 1000).round(1)
        Taski::Logging.debug(Taski::Logging::Events::TASK_CLEAN_COMPLETED, task: task_class.name, duration_ms: duration)
        wrapper.mark_clean_completed(result)
        @completion_queue.push(FiberProtocol::CleanCompleted.new(task_class, wrapper))
      rescue => e
        @registry.request_abort! if e.is_a?(Taski::TaskAbortException)
        duration = ((Time.now - clean_start) * 1000).round(1) if clean_start
        Taski::Logging.warn(Taski::Logging::Events::TASK_CLEAN_FAILED, task: task_class.name, duration_ms: duration)
        wrapper.mark_clean_failed(e)
        @completion_queue.push(FiberProtocol::CleanFailed.new(task_class, wrapper, e))
      ensure
        stop_output_capture
        teardown_thread_locals
      end

      # Clean task dropped because abort was requested before its worker
      # dequeued it. Push a terminal clean event so run_clean_main_loop does
      # not block forever on completion_queue.pop.
      def abort_unstarted_clean_task(task_class, wrapper)
        error = Taski::TaskAbortException.new("Execution aborted before #{task_class.name} clean started")
        wrapper.mark_clean_failed(error)
        @completion_queue.push(FiberProtocol::CleanFailed.new(task_class, wrapper, error))
      end

      # Set up context for clean execution (no Fiber flag).
      def setup_clean_thread_locals
        Thread.current[:taski_current_phase] = :clean
        ExecutionFacade.current = @execution_facade
        Taski.set_current_registry(@registry)
        Taski.set_current_args(@run_args)
        Taski.set_current_env(@run_env)
      end

      def setup_run_thread_locals
        Thread.current[:taski_fiber_context] = true
        Thread.current[:taski_current_phase] = :run
        ExecutionFacade.current = @execution_facade
        Taski.set_current_registry(@registry)
        Taski.set_current_args(@run_args)
        Taski.set_current_env(@run_env)
      end

      def teardown_thread_locals
        Thread.current[:taski_fiber_context] = nil
        Thread.current[:taski_current_phase] = nil
        ExecutionFacade.current = nil
        Taski.clear_current_registry
        Taski.reset_args!
        Taski.reset_env!
      end

      def task_duration_ms(task_class)
        start = @task_start_times_mutex.synchronize { @task_start_times.delete(task_class) }
        return nil unless start
        ((Time.now - start) * 1000).round(1)
      end

      def start_output_capture(task_class)
        output_capture = @execution_facade.output_capture
        output_capture&.start_capture(task_class)
      end

      def stop_output_capture
        output_capture = @execution_facade.output_capture
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
    end
  end
end
