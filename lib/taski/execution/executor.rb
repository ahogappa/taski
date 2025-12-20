# frozen_string_literal: true

require "monitor"

module Taski
  module Execution
    # Producer-Consumer pattern executor for parallel task execution.
    #
    # Architecture:
    # - Main Thread: Manages all state, coordinates execution, handles events
    # - Worker Threads: Execute tasks and send completion events (via WorkerPool)
    # - Scheduler: Manages dependency state and determines execution order
    # - ExecutionContext: Manages observers and output capture
    #
    # Communication Queues:
    # - Execution Queue (Main -> Worker): Tasks ready to execute (via WorkerPool)
    # - Completion Queue (Worker -> Main): Events from workers
    class Executor
      class << self
        # Execute a task and all its dependencies
        # @param root_task_class [Class] The root task class to execute
        # @param registry [Registry] The task registry
        # @param execution_context [ExecutionContext, nil] Optional execution context
        def execute(root_task_class, registry:, execution_context: nil)
          new(registry: registry, execution_context: execution_context).execute(root_task_class)
        end
      end

      def initialize(registry:, worker_count: nil, execution_context: nil)
        @registry = registry
        @completion_queue = Queue.new

        # ExecutionContext for observer pattern and output capture
        @execution_context = execution_context || create_default_execution_context

        # Scheduler for dependency management
        @scheduler = Scheduler.new

        # WorkerPool for thread management
        @worker_pool = WorkerPool.new(
          registry: @registry,
          worker_count: worker_count
        ) { |task_class, wrapper| execute_task(task_class, wrapper) }
      end

      # Execute root task and all dependencies
      # @param root_task_class [Class] The root task class to execute
      def execute(root_task_class)
        # Build dependency graph from static analysis
        @scheduler.build_dependency_graph(root_task_class)

        # Set up progress display with root task and output capture
        setup_progress_display(root_task_class)

        # Start progress display
        start_progress_display

        # Start worker threads
        @worker_pool.start

        # Enqueue tasks with no dependencies
        enqueue_ready_tasks

        # Main event loop - continues until root task completes
        run_main_loop(root_task_class)

        # Shutdown workers
        @worker_pool.shutdown

        # Stop progress display
        stop_progress_display

        # Restore original stdout
        teardown_output_capture
      end

      private

      # Enqueue all tasks that are ready to execute
      def enqueue_ready_tasks
        @scheduler.next_ready_tasks.each do |task_class|
          enqueue_task(task_class)
        end
      end

      # Enqueue a single task for execution
      def enqueue_task(task_class)
        return if @registry.abort_requested?

        @scheduler.mark_enqueued(task_class)

        wrapper = get_or_create_wrapper(task_class)
        return unless wrapper.mark_running

        @execution_context.notify_task_registered(task_class)
        @execution_context.notify_task_started(task_class)

        @worker_pool.enqueue(task_class, wrapper)
      end

      # Get or create a task wrapper via Registry
      def get_or_create_wrapper(task_class)
        @registry.get_or_create(task_class) do
          task_instance = task_class.allocate
          task_instance.send(:initialize)
          TaskWrapper.new(task_instance, registry: @registry, execution_context: @execution_context)
        end
      end

      # Execute a task and send completion event (called by WorkerPool)
      def execute_task(task_class, wrapper)
        return if @registry.abort_requested?

        output_capture = @execution_context.output_capture

        # Start capturing output for this task
        output_capture&.start_capture(task_class)

        # Set thread-local execution context for task access (e.g., Section)
        ExecutionContext.current = @execution_context

        begin
          result = wrapper.task.run
          wrapper.mark_completed(result)
          @completion_queue.push({task_class: task_class, wrapper: wrapper})
        rescue Taski::TaskAbortException => e
          @registry.request_abort!
          wrapper.mark_failed(e)
          @completion_queue.push({task_class: task_class, wrapper: wrapper, error: e})
        rescue => e
          wrapper.mark_failed(e)
          @completion_queue.push({task_class: task_class, wrapper: wrapper, error: e})
        ensure
          # Stop capturing output for this task
          output_capture&.stop_capture
          # Clear thread-local execution context
          ExecutionContext.current = nil
        end
      end

      # Main thread event loop - continues until root task completes
      def run_main_loop(root_task_class)
        until @scheduler.completed?(root_task_class)
          break if @registry.abort_requested? && !@scheduler.running_tasks?

          event = @completion_queue.pop
          handle_completion(event)
        end
      end

      # Handle task completion event
      def handle_completion(event)
        task_class = event[:task_class]

        debug_log("Completed: #{task_class}")

        @scheduler.mark_completed(task_class)

        # Enqueue newly ready tasks
        enqueue_ready_tasks
      end

      def setup_progress_display(root_task_class)
        @execution_context.notify_set_root_task(root_task_class)

        # Set up output capture for inline display (only for TTY)
        @execution_context.setup_output_capture($stdout)
      end

      def teardown_output_capture
        @execution_context.teardown_output_capture
      end

      def start_progress_display
        @execution_context.notify_start
      end

      def stop_progress_display
        @execution_context.notify_stop
      end

      def create_default_execution_context
        context = ExecutionContext.new
        progress = Taski.progress_display
        context.add_observer(progress) if progress

        # Set execution trigger to break circular dependency with TaskWrapper
        context.execution_trigger = ->(task_class, registry) do
          Executor.execute(task_class, registry: registry, execution_context: context)
        end

        context
      end

      def debug_log(message)
        return unless ENV["TASKI_DEBUG"]
        puts "[Executor] #{message}"
      end
    end
  end
end
