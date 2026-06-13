# frozen_string_literal: true

require "etc"

module Taski
  module Execution
    # Orchestrates run (Fiber-based) and clean (direct) phases of task execution.
    # Delegates to Scheduler (state tracking / advisory proposals),
    # WorkerPool (worker threads), and ExecutionFacade (observer notifications).
    #
    # Task execution is driven by the Fiber pull model — tasks start only when
    # requested via Fiber.yield FiberProtocol::NeedDep. Scheduler may propose tasks,
    # but Executor/Wrapper can reject proposals not backed by actual Fiber requests.
    class Executor
      class << self
        def execute(root_task_class, registry:, execution_facade:)
          new(registry: registry, execution_facade: execution_facade).execute(root_task_class)
        end

        def execute_clean(root_task_class, registry:, execution_facade:)
          new(registry: registry, execution_facade: execution_facade).execute_clean(root_task_class)
        end
      end

      def initialize(registry:, execution_facade:, worker_count: nil)
        @registry = registry
        @completion_queue = Queue.new
        @execution_facade = execution_facade
        @scheduler = Scheduler.new
        @effective_worker_count = worker_count || Taski.args_worker_count
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

          begin
            @worker_pool.start

            enqueue_root_if_needed(root_task_class)

            run_main_loop(root_task_class)

            notify_skipped_tasks
          ensure
            # Always shut the pool down — otherwise a raise in the main loop
            # leaves worker threads blocked on queue.pop forever.
            @worker_pool.shutdown
          end
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
          begin
            @worker_pool.start
            enqueue_ready_clean_tasks
            run_clean_main_loop
          ensure
            # Always shut the pool down so a raise in the clean loop cannot
            # leak worker threads.
            @worker_pool.shutdown
          end
        end

        raise_if_any_clean_failures
      end

      private

      # Run phase

      def enqueue_root_if_needed(root_task_class)
        return unless @scheduler.pending?(root_task_class)

        enqueue_for_execution(root_task_class)
      end

      def run_main_loop(root_task_class)
        # Wait for the root AND every still-running (speculatively prestarted)
        # task. Exiting on the root alone abandons parked fibers: shutdown's
        # :shutdown sentinel reaches a parked task's worker before the Resume
        # its slow dep pushes on completion, so the fiber dies mid-run — its
        # ensure never executes and its wrapper is stuck :running while run()
        # reports success. Every task marked running is guaranteed a terminal
        # completion-queue event (StartDepNotify is pushed before its Execute
        # command), so waiting here cannot deadlock.
        until @scheduler.finished?(root_task_class) && !@scheduler.running_tasks?
          break if @registry.abort_requested? && !@scheduler.running_tasks?

          event = @completion_queue.pop
          case event
          in FiberProtocol::StartDepNotify => notify
            @scheduler.mark_running(notify.task_class)
          in FiberProtocol::TaskCompleted | FiberProtocol::TaskFailed
            handle_completion(event)
          else
            raise "[BUG] unexpected completion queue event: #{event.inspect}"
          end
        end
      end

      def handle_completion(event)
        task_class = event.task_class
        Taski::Logging.debug(Taski::Logging::Events::EXECUTOR_TASK_COMPLETED, task: task_class.name)

        case event
        in FiberProtocol::TaskFailed => failed
          @scheduler.mark_failed(failed.task_class)
          log_error_detail(failed.task_class, failed.error)
          skip_pending_dependents(failed.task_class)
        in FiberProtocol::TaskCompleted
          @scheduler.mark_completed(task_class)
        else
          raise "[BUG] unexpected run completion event: #{event.inspect}"
        end
      end

      def enqueue_for_execution(task_class)
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
        task_class = event.task_class
        Taski::Logging.debug(Taski::Logging::Events::EXECUTOR_CLEAN_COMPLETED, task: task_class.name)

        case event
        in FiberProtocol::CleanFailed => failed
          @scheduler.mark_clean_failed(failed.task_class)
        in FiberProtocol::CleanCompleted
          @scheduler.mark_clean_completed(task_class)
        else
          raise "[BUG] unexpected clean completion event: #{event.inspect}"
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
          error_accessor: ->(w) { w.error },
          order_accessor: ->(w) { w.failed_order || Float::INFINITY }
        )
      end

      def raise_if_any_clean_failures
        raise_if_any_failures_from(
          @registry.failed_clean_wrappers,
          error_accessor: ->(w) { w.clean_error },
          order_accessor: ->(w) { w.clean_failed_order || Float::INFINITY }
        )
      end

      def raise_if_any_failures_from(failed_wrappers, error_accessor:, order_accessor:)
        return if failed_wrappers.empty?

        abort_wrapper = failed_wrappers.find { |w| error_accessor.call(w).is_a?(TaskAbortException) }
        raise error_accessor.call(abort_wrapper) if abort_wrapper

        # Attribute each unique error to its ORIGIN: a dependency failure
        # re-raises the same error object in every waiter up the requester
        # chain, and the dedup below keeps the first occurrence — so order
        # the wrappers chronologically (in the run phase a waiter can only
        # fail AFTER its dependency's mark_failed, so the origin stamps
        # first; clean-phase failures have no such propagation ordering, but
        # there a shared error object means both attributions are true).
        # Registry order would attribute the error to whichever wrapper was
        # created first, typically the root.
        #
        # Failures spliced from a nested executor's AggregateError are
        # already origin-attributed by that executor — prefer them over a
        # wrapper-level entry for the same error regardless of stamp order.
        ordered = failed_wrappers.sort_by { |w| order_accessor.call(w) }
        unique = {}
        flatten_failures_from(ordered, error_accessor: error_accessor) do |failure, origin_attributed|
          key = error_identity(failure.error)
          existing = unique[key]
          unique[key] = [failure, origin_attributed] if existing.nil? || (origin_attributed && !existing[1])
        end

        raise AggregateError.new(unique.values.map(&:first))
      end

      # Yields [TaskFailure, origin_attributed] for each failure entry.
      # origin_attributed is true for failures spliced from a nested
      # AggregateError (the nested executor already named the origin task).
      def flatten_failures_from(failed_wrappers, error_accessor:)
        output_capture = @saved_output_capture

        failed_wrappers.each do |wrapper|
          error = error_accessor.call(wrapper)
          case error
          when AggregateError
            error.errors.each { |failure| yield failure, true }
          else
            wrapped_error = wrap_with_task_error(wrapper.task.class, error)
            output_lines = output_capture&.read(wrapper.task.class) || []
            yield TaskFailure.new(task_class: wrapper.task.class, error: wrapped_error, output_lines: output_lines), false
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
