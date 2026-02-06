# frozen_string_literal: true

require "etc"

module Taski
  module Execution
    # Executor orchestrates both run and clean phases of task execution.
    #
    # == Architecture
    #
    #   Executor
    #     ├── Scheduler: Dependency management and execution order
    #     ├── WorkerPool: Fiber-based task execution on worker threads
    #     ├── SharedState: Centralized state for Fiber coordination
    #     └── ExecutionContext: Observer notifications and output capture
    #             └── Observers (e.g., TreeProgressDisplay)
    #
    # == Run Phase (Fiber-based)
    #
    # 1. Build dependency graph via Scheduler
    # 2. Set up progress display via ExecutionContext
    # 3. Start WorkerPool (Fiber-based worker threads)
    # 4. Pre-start leaf tasks for parallelism
    # 5. Run event loop:
    #    - Pop completion events from workers
    #    - Mark completed in Scheduler
    #    - Enqueue newly ready tasks to WorkerPool
    # 6. Shutdown WorkerPool when root task completes
    # 7. Teardown progress display
    #
    # == Clean Phase
    #
    # Uses WorkerPool (no Fibers needed, direct execution).
    # Runs tasks in reverse dependency order.
    class Executor
      class << self
        # Execute a task and all its dependencies using Fiber-based execution.
        # @param root_task_class [Class] The root task class to execute
        # @param registry [Registry] The task registry
        # @param execution_context [ExecutionContext, nil] Optional execution context
        def execute(root_task_class, registry:, execution_context: nil)
          new(registry: registry, execution_context: execution_context).execute(root_task_class)
        end

        # Execute clean for a task and all its dependencies (in reverse order).
        # @param root_task_class [Class] The root task class to clean
        # @param registry [Registry] The task registry
        # @param execution_context [ExecutionContext, nil] Optional execution context
        def execute_clean(root_task_class, registry:, execution_context: nil)
          new(registry: registry, execution_context: execution_context).execute_clean(root_task_class)
        end
      end

      # @param registry [Registry] Task registry
      # @param worker_count [Integer, nil] Number of worker threads
      # @param execution_context [ExecutionContext, nil] For observer notifications
      def initialize(registry:, worker_count: nil, execution_context: nil)
        @registry = registry
        @completion_queue = Queue.new
        @execution_context = execution_context || create_default_execution_context
        @scheduler = Scheduler.new
        @effective_worker_count = worker_count || Taski.args_worker_count
        @shared_state = SharedState.new
        @enqueued_tasks = Set.new
      end

      # Execute the task graph rooted at the given task class.
      # @param root_task_class [Class] The root task class to execute
      def execute(root_task_class)
        start_time = Time.now

        log_execution_started(root_task_class)

        @scheduler.build_dependency_graph(root_task_class)

        with_display_lifecycle(root_task_class) do
          @worker_pool = WorkerPool.new(
            shared_state: @shared_state,
            registry: @registry,
            execution_context: @execution_context,
            worker_count: @effective_worker_count,
            completion_queue: @completion_queue
          )

          @worker_pool.start

          pre_start_leaf_tasks

          enqueue_root_if_needed(root_task_class)

          run_main_loop(root_task_class)

          @worker_pool.shutdown

          notify_skipped_tasks
        end

        log_execution_completed(root_task_class, start_time)

        raise_if_any_failures
      end

      # Execute clean for root task and all dependencies (in reverse dependency order).
      # @param root_task_class [Class] The root task class to clean
      def execute_clean(root_task_class)
        @scheduler.build_reverse_dependency_graph(root_task_class)

        with_display_lifecycle(root_task_class) do
          @worker_pool = WorkerPool.new(
            shared_state: @shared_state,
            registry: @registry,
            execution_context: @execution_context,
            worker_count: @effective_worker_count,
            completion_queue: @completion_queue
          )
          @worker_pool.start
          enqueue_ready_clean_tasks
          run_clean_main_loop(root_task_class)
          @worker_pool.shutdown
        end

        raise_if_any_clean_failures
      end

      private

      # ========================================
      # Run Phase Methods (Fiber-based)
      # ========================================

      # Pre-start leaf tasks (tasks with no dependencies) for parallelism.
      def pre_start_leaf_tasks
        @scheduler.next_ready_tasks.each { |task_class| enqueue_for_execution(task_class) }
      end

      # Enqueue the root task if it wasn't already started as a leaf.
      def enqueue_root_if_needed(root_task_class)
        return if @scheduler.completed?(root_task_class)
        return if @enqueued_tasks.include?(root_task_class)

        enqueue_for_execution(root_task_class)
      end

      # Main event loop - wait for tasks to complete.
      def run_main_loop(root_task_class)
        until @scheduler.completed?(root_task_class)
          break if @registry.abort_requested? && !@scheduler.running_tasks?

          event = @completion_queue.pop
          handle_completion(event)
        end
      end

      def handle_completion(event)
        task_class = event[:task_class]
        debug_log("Completed: #{task_class}")
        @scheduler.mark_completed(task_class)

        @scheduler.next_ready_tasks.each do |ready_class|
          next if @enqueued_tasks.include?(ready_class)
          enqueue_for_execution(ready_class)
        end
      end

      def enqueue_for_execution(task_class)
        @scheduler.mark_enqueued(task_class)
        @enqueued_tasks.add(task_class)
        wrapper = @registry.create_wrapper(task_class, execution_context: @execution_context)
        @shared_state.register(task_class, wrapper)
        @worker_pool.enqueue(task_class, wrapper)
      end

      # Notify observers about tasks that were in the static dependency graph
      # but never executed (remained in STATE_PENDING).
      def notify_skipped_tasks
        @scheduler.skipped_task_classes.each do |task_class|
          @execution_context.notify_task_registered(task_class)
          @execution_context.notify_task_skipped(task_class)
        end
      end

      # ========================================
      # Clean Phase Methods
      # ========================================

      def enqueue_ready_clean_tasks
        @scheduler.next_ready_clean_tasks.each do |task_class|
          enqueue_clean_task(task_class)
        end
      end

      def enqueue_clean_task(task_class)
        return if @registry.abort_requested?

        @scheduler.mark_clean_enqueued(task_class)

        wrapper = @registry.create_wrapper(task_class, execution_context: @execution_context)
        return unless wrapper.mark_clean_running

        @execution_context.notify_clean_started(task_class)

        @worker_pool.enqueue_clean(task_class, wrapper)
      end

      def run_clean_main_loop(root_task_class)
        until all_tasks_cleaned?
          break if @registry.abort_requested? && !@scheduler.running_clean_tasks?

          event = @completion_queue.pop
          handle_clean_completion(event)
        end
      end

      def handle_clean_completion(event)
        task_class = event[:task_class]
        debug_log("Clean completed: #{task_class}")
        @scheduler.mark_clean_completed(task_class)
        enqueue_ready_clean_tasks
      end

      def all_tasks_cleaned?
        @scheduler.next_ready_clean_tasks.empty? && !@scheduler.running_clean_tasks?
      end

      # ========================================
      # Display Lifecycle
      # ========================================

      def with_display_lifecycle(root_task_class)
        setup_progress_display(root_task_class)
        should_teardown_capture = setup_output_capture_if_needed
        start_progress_display

        yield
      ensure
        stop_progress_display
        @saved_output_capture = @execution_context.output_capture
        teardown_output_capture if should_teardown_capture
      end

      def setup_progress_display(root_task_class)
        @execution_context.notify_set_root_task(root_task_class)
      end

      def setup_output_capture_if_needed
        return false unless Taski.progress_display
        return false if @execution_context.output_capture_active?

        @execution_context.setup_output_capture($stdout)
        true
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

      # ========================================
      # Error Handling
      # ========================================

      def raise_if_any_failures
        raise_if_any_failures_from(
          @registry.failed_wrappers,
          error_accessor: ->(w) { w.error }
        )
      end

      def raise_if_any_clean_failures
        raise_if_any_failures_from(
          @registry.failed_clean_wrappers,
          error_accessor: ->(w) { w.clean_error }
        )
      end

      def raise_if_any_failures_from(failed_wrappers, error_accessor:)
        return if failed_wrappers.empty?

        abort_wrapper = failed_wrappers.find { |w| error_accessor.call(w).is_a?(TaskAbortException) }
        raise error_accessor.call(abort_wrapper) if abort_wrapper

        failures = flatten_failures_from(failed_wrappers, error_accessor: error_accessor)
        unique_failures = failures.uniq { |f| error_identity(f.error) }

        raise AggregateError.new(unique_failures)
      end

      def flatten_failures_from(failed_wrappers, error_accessor:)
        output_capture = @saved_output_capture

        failed_wrappers.flat_map do |wrapper|
          error = error_accessor.call(wrapper)
          case error
          when AggregateError
            error.errors
          else
            wrapped_error = wrap_with_task_error(wrapper.task.class, error)
            output_lines = output_capture&.recent_lines_for(wrapper.task.class) || []
            [TaskFailure.new(task_class: wrapper.task.class, error: wrapped_error, output_lines: output_lines)]
          end
        end
      end

      def wrap_with_task_error(task_class, error)
        return error if error.is_a?(TaskError)
        error_class = task_class.const_get(:Error)
        error_class.new(error, task_class: task_class)
      end

      def error_identity(error)
        error.is_a?(TaskError) ? error.cause&.object_id || error.object_id : error.object_id
      end

      # ========================================
      # Logging
      # ========================================

      def create_default_execution_context
        context = ExecutionContext.new
        progress = Taski.progress_display
        context.add_observer(progress) if progress

        if Taski.logger
          context.add_observer(Taski::Logging::LoggerObserver.new)
        end

        context.execution_trigger = ->(task_class, registry) do
          Executor.execute(task_class, registry: registry, execution_context: context)
        end

        context
      end

      def log_execution_started(root_task_class)
        Taski::Logging.info(
          Taski::Logging::Events::EXECUTION_STARTED,
          task: root_task_class.name,
          worker_count: @effective_worker_count || Execution.default_worker_count
        )
      end

      def log_execution_completed(root_task_class, start_time)
        duration_ms = ((Time.now - start_time) * 1000).round(1)
        Taski::Logging.info(
          Taski::Logging::Events::EXECUTION_COMPLETED,
          task: root_task_class.name,
          duration_ms: duration_ms,
          task_count: @scheduler.task_count,
          skipped_count: @scheduler.skipped_task_classes.size
        )
      end

      def debug_log(message)
        return unless ENV["TASKI_DEBUG"]
        puts "[Executor] #{message}"
      end
    end
  end
end
