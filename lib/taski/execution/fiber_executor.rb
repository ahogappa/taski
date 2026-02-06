# frozen_string_literal: true

module Taski
  module Execution
    # FiberExecutor orchestrates the Fiber-based run phase.
    # It uses Scheduler for static dependency analysis and FiberWorkerPool
    # for Fiber-based task execution with lazy dependency resolution.
    #
    # The clean phase is NOT handled by FiberExecutor - it remains in the
    # original Executor using Monitor-based synchronization.
    class FiberExecutor
      # @param registry [Registry] Task registry
      # @param execution_context [ExecutionContext] For observer notifications
      # @param worker_count [Integer, nil] Number of worker threads
      def initialize(registry:, execution_context: nil, worker_count: nil)
        @registry = registry
        @execution_context = execution_context || create_default_execution_context
        @scheduler = Scheduler.new
        @effective_worker_count = worker_count || Taski.args_worker_count
        @shared_state = SharedState.new
        @completion_queue = Queue.new
        @enqueued_tasks = Set.new
      end

      # Execute the task graph rooted at the given task class.
      # @param root_task_class [Class] The root task class
      def execute(root_task_class)
        start_time = Time.now

        log_execution_started(root_task_class)

        # Build dependency graph from static analysis
        @scheduler.build_dependency_graph(root_task_class)

        with_display_lifecycle(root_task_class) do
          # Create FiberWorkerPool
          @fiber_pool = FiberWorkerPool.new(
            shared_state: @shared_state,
            registry: @registry,
            execution_context: @execution_context,
            worker_count: @effective_worker_count,
            completion_queue: @completion_queue
          )

          @fiber_pool.start

          # Pre-register and pre-start leaf tasks for parallelism
          pre_start_leaf_tasks

          # Start root task (if not already started as a leaf)
          enqueue_root_if_needed(root_task_class)

          # Main event loop
          run_main_loop(root_task_class)

          @fiber_pool.shutdown

          notify_skipped_tasks
        end

        log_execution_completed(root_task_class, start_time)

        raise_if_any_failures
      end

      private

      # Pre-start leaf tasks (tasks with no dependencies) for parallelism.
      def pre_start_leaf_tasks
        @scheduler.next_ready_tasks.each do |task_class|
          @scheduler.mark_enqueued(task_class)
          @enqueued_tasks.add(task_class)
          wrapper = get_or_create_wrapper(task_class)
          @shared_state.register(task_class, wrapper)
          @fiber_pool.enqueue(task_class, wrapper)
        end
      end

      # Enqueue the root task if it wasn't already started as a leaf.
      def enqueue_root_if_needed(root_task_class)
        return if @scheduler.completed?(root_task_class)
        return if @enqueued_tasks.include?(root_task_class)

        wrapper = get_or_create_wrapper(root_task_class)
        @shared_state.register(root_task_class, wrapper)
        @scheduler.mark_enqueued(root_task_class)
        @enqueued_tasks.add(root_task_class)
        @fiber_pool.enqueue(root_task_class, wrapper)
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

        # Enqueue newly ready tasks (tasks whose deps are now all complete)
        @scheduler.next_ready_tasks.each do |ready_class|
          next if @enqueued_tasks.include?(ready_class)
          @scheduler.mark_enqueued(ready_class)
          @enqueued_tasks.add(ready_class)
          wrapper = get_or_create_wrapper(ready_class)
          @shared_state.register(ready_class, wrapper)
          @fiber_pool.enqueue(ready_class, wrapper)
        end
      end

      # Notify observers about tasks that were in the static dependency graph
      # but never executed (remained in STATE_PENDING).
      def notify_skipped_tasks
        @scheduler.skipped_task_classes.each do |task_class|
          @execution_context.notify_task_registered(task_class)
          @execution_context.notify_task_skipped(task_class)
        end
      end

      def get_or_create_wrapper(task_class)
        @registry.get_or_create(task_class) do
          task_instance = task_class.allocate
          task_instance.send(:initialize)
          TaskWrapper.new(task_instance, registry: @registry, execution_context: @execution_context)
        end
      end

      # ========================================
      # Display lifecycle (reused from Executor)
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
      # Error handling (reused from Executor)
      # ========================================

      def raise_if_any_failures
        failed = @registry.failed_wrappers
        return if failed.empty?

        abort_wrapper = failed.find { |w| w.error.is_a?(TaskAbortException) }
        raise abort_wrapper.error if abort_wrapper

        failures = flatten_failures(failed)
        unique_failures = failures.uniq { |f| error_identity(f.error) }
        raise AggregateError.new(unique_failures)
      end

      def flatten_failures(failed_wrappers)
        output_capture = @saved_output_capture

        failed_wrappers.flat_map do |wrapper|
          error = wrapper.error
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

      def create_default_execution_context
        context = ExecutionContext.new
        progress = Taski.progress_display
        context.add_observer(progress) if progress

        if Taski.logger
          context.add_observer(Taski::Logging::LoggerObserver.new)
        end

        context.execution_trigger = ->(task_class, registry) do
          FiberExecutor.new(
            registry: registry,
            execution_context: context
          ).execute(task_class)
        end

        context
      end

      def log_execution_started(root_task_class)
        Taski::Logging.info(
          Taski::Logging::Events::EXECUTION_STARTED,
          task: root_task_class.name,
          worker_count: @effective_worker_count || Etc.nprocessors.clamp(2, 8)
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
        puts "[FiberExecutor] #{message}"
      end
    end
  end
end
