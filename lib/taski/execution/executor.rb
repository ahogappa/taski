# frozen_string_literal: true

require "etc"

module Taski
  module Execution
    # Orchestrates run (Fiber-based) and clean (direct) phases of task execution.
    # Delegates to Scheduler (dependency order), WorkerPool (worker threads),
    # and ExecutionFacade (observer notifications).
    class Executor
      class << self
        def execute(root_task_class, registry:, execution_facade: nil)
          new(root_task_class: root_task_class, registry: registry, execution_facade: execution_facade).execute(root_task_class)
        end

        def execute_clean(root_task_class, registry:, execution_facade: nil)
          new(root_task_class: root_task_class, registry: registry, execution_facade: execution_facade).execute_clean(root_task_class)
        end
      end

      def initialize(registry:, root_task_class: nil, worker_count: nil, execution_facade: nil)
        @root_task_class = root_task_class
        @registry = registry
        @completion_queue = Queue.new
        @execution_facade = execution_facade || create_default_facade
        @scheduler = Scheduler.new
        @effective_worker_count = worker_count || Taski.args_worker_count
        @enqueued_tasks = Set.new
      end

      def execute(root_task_class)
        start_time = Time.now

        log_execution_started(root_task_class)

        @scheduler.load_graph(@execution_facade.dependency_graph, root_task_class)

        with_display_lifecycle(root_task_class) do
          @worker_pool = WorkerPool.new(
            registry: @registry,
            execution_facade: @execution_facade,
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

      def execute_clean(root_task_class)
        @scheduler.load_graph(@execution_facade.dependency_graph, root_task_class)
        @scheduler.build_reverse_dependency_graph

        with_display_lifecycle(root_task_class) do
          @worker_pool = WorkerPool.new(
            registry: @registry,
            execution_facade: @execution_facade,
            worker_count: @effective_worker_count,
            completion_queue: @completion_queue
          )
          @worker_pool.start
          enqueue_ready_clean_tasks
          run_clean_main_loop
          @worker_pool.shutdown
        end

        raise_if_any_clean_failures
      end

      private

      # Run phase

      def pre_start_leaf_tasks
        @scheduler.next_ready_tasks.each { |task_class| enqueue_for_execution(task_class) }
      end

      def enqueue_root_if_needed(root_task_class)
        return if @scheduler.completed?(root_task_class)
        return if @enqueued_tasks.include?(root_task_class)

        enqueue_for_execution(root_task_class)
      end

      def run_main_loop(root_task_class)
        until @scheduler.completed?(root_task_class)
          break if @registry.abort_requested? && !@scheduler.running_tasks?

          event = @completion_queue.pop
          handle_completion(event)
        end
      end

      def handle_completion(event)
        task_class = event[:task_class]
        Taski::Logging.debug(Taski::Logging::Events::EXECUTOR_TASK_COMPLETED, task: task_class.name)

        # Skip dynamic-only tasks not in the static graph
        return unless @enqueued_tasks.include?(task_class)

        if event[:error]
          @scheduler.mark_failed(task_class)
          log_error_detail(task_class, event[:error])
          skip_pending_dependents(task_class)
        else
          @scheduler.mark_completed(task_class)
        end

        @scheduler.next_ready_tasks.each do |ready_class|
          next if @enqueued_tasks.include?(ready_class)
          enqueue_for_execution(ready_class)
        end
      end

      def enqueue_for_execution(task_class)
        @enqueued_tasks.add(task_class)
        wrapper = @registry.create_wrapper(task_class, execution_facade: @execution_facade)
        @scheduler.mark_running(task_class)
        if wrapper.mark_running
          @worker_pool.enqueue(task_class, wrapper)
        end
        # If mark_running fails: Fiber path already claimed this task.
        # Completion event will arrive through completion_queue.
      end

      # Skip pending dependents of a failed task (only those not yet started).
      def skip_pending_dependents(failed_task_class)
        now = Time.now
        @scheduler.pending_dependents_of(failed_task_class).each do |dep_class|
          next if @registry.registered?(dep_class)

          @scheduler.mark_skipped(dep_class)
          Taski::Logging.info(Taski::Logging::Events::TASK_SKIPPED, task: dep_class.name)
          @execution_facade.notify_task_updated(dep_class, previous_state: :pending, current_state: :skipped, phase: :run, timestamp: now)
        end
      end

      # Transition remaining pending tasks to skipped state.
      def notify_skipped_tasks
        now = Time.now
        @scheduler.never_started_task_classes.each do |task_class|
          @scheduler.mark_skipped(task_class)
          Taski::Logging.info(Taski::Logging::Events::TASK_SKIPPED, task: task_class.name)
          @execution_facade.notify_task_updated(task_class, previous_state: nil, current_state: :pending, phase: :run, timestamp: now)
          @execution_facade.notify_task_updated(task_class, previous_state: :pending, current_state: :skipped, phase: :run, timestamp: now)
        end
      end

      # Clean phase

      def enqueue_ready_clean_tasks
        # Loops because skipped tasks immediately unlock further dependents.
        loop do
          newly_ready = @scheduler.next_ready_clean_tasks
          break if newly_ready.empty?

          newly_ready.each do |task_class|
            enqueue_clean_task(task_class)
          end
        end
      end

      def enqueue_clean_task(task_class)
        return if @registry.abort_requested?

        # Skip tasks never executed during run phase.
        unless @registry.registered?(task_class)
          @scheduler.mark_clean_completed(task_class)
          return
        end

        @scheduler.mark_clean_running(task_class)

        wrapper = @registry.create_wrapper(task_class, execution_facade: @execution_facade)
        return unless wrapper.mark_clean_running

        @execution_facade.notify_task_updated(task_class, previous_state: :pending, current_state: :running, phase: :clean, timestamp: Time.now)

        @worker_pool.enqueue_clean(task_class, wrapper)
      end

      def run_clean_main_loop
        until all_tasks_cleaned?
          break if @registry.abort_requested? && !@scheduler.running_clean_tasks?

          event = @completion_queue.pop
          handle_clean_completion(event)
        end
      end

      def handle_clean_completion(event)
        task_class = event[:task_class]
        Taski::Logging.debug(Taski::Logging::Events::EXECUTOR_CLEAN_COMPLETED, task: task_class.name)
        if event[:error]
          @scheduler.mark_clean_failed(task_class)
        else
          @scheduler.mark_clean_completed(task_class)
        end
        enqueue_ready_clean_tasks
      end

      def all_tasks_cleaned?
        @scheduler.next_ready_clean_tasks.empty? && !@scheduler.running_clean_tasks?
      end

      # Display lifecycle

      def with_display_lifecycle(root_task_class)
        should_teardown_capture = setup_output_capture_if_needed
        @execution_facade.notify_ready
        @execution_facade.notify_start

        yield
      ensure
        @execution_facade.notify_stop
        @saved_output_capture = @execution_facade.output_capture
        @execution_facade.teardown_output_capture if should_teardown_capture
      end

      def setup_output_capture_if_needed
        return false unless Taski.progress_display
        return false if @execution_facade.output_capture_active?

        @execution_facade.setup_output_capture($stdout)
        true
      end

      # Error handling

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
            output_lines = output_capture&.read(wrapper.task.class) || []
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

      # Context and logging

      def create_default_facade
        ExecutionFacade.build_default(root_task_class: @root_task_class)
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
          skipped_count: @scheduler.skipped_count
        )
      end

      def log_error_detail(task_class, error)
        Taski::Logging.error(
          Taski::Logging::Events::TASK_ERROR_DETAIL,
          task: task_class.name,
          error_class: error.class.name,
          error_message: error.message,
          backtrace: error.backtrace&.first(10)
        )
      end
    end
  end
end
