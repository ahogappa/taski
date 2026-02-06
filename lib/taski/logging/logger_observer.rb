# frozen_string_literal: true

require_relative "../execution/task_observer"

module Taski
  module Logging
    # LoggerObserver implements the TaskObserver interface
    # to emit structured log events for task execution lifecycle.
    #
    # This observer is automatically registered when Taski.logger is set.
    # It uses the Pull API to access context information like the current phase
    # and dependency graph.
    #
    # == Events Logged
    #
    # - execution.ready - When execution is ready with total task count
    # - task.started - When a task begins execution
    # - task.completed - When a task completes with duration
    # - task.failed - When a task fails with error details
    # - task.skipped - When a task is skipped (e.g., unselected Section candidate)
    # - task.clean_started - When clean phase begins for a task
    # - task.clean_completed - When clean phase completes for a task
    # - task.clean_failed - When clean phase fails for a task
    #
    # == Usage
    #
    # LoggerObserver is typically registered automatically when Taski.logger is set:
    #
    #   require 'logger'
    #   Taski.logger = Logger.new($stderr, level: Logger::INFO)
    #
    # For custom integration with ExecutionFacade:
    #
    #   context = Taski::Execution::ExecutionFacade.new
    #   observer = Taski::Logging::LoggerObserver.new
    #   context.add_observer(observer)
    #   # observer.context is automatically set to context
    #
    # == Pull API Usage
    #
    # The observer uses the injected context to pull information:
    #
    #   def on_ready
    #     graph = context.dependency_graph  # Pull static dependency graph
    #     total = graph.all_tasks.size
    #   end
    #
    #   def on_task_updated(task_class, ...)
    #     phase = context.current_phase     # Pull current phase (:run or :clean)
    #   end
    #
    class LoggerObserver < Taski::Execution::TaskObserver
      def initialize
        super
        @task_start_times = {}
      end

      # Called when execution is ready (root task and dependencies resolved).
      # Logs the total task count from the dependency graph.
      def on_ready
        graph = facade&.dependency_graph
        total_tasks = graph&.all_tasks&.size || 0

        Logging.info(
          Events::EXECUTION_READY,
          total_tasks: total_tasks
        )
      end

      # Unified event interface for task state transitions
      # Note: error is NOT passed via notification - exceptions propagate to top level (Plan design)
      # @param task_class [Class] The task class
      # @param previous_state [Symbol] The previous state
      # @param current_state [Symbol] The new state
      # @param timestamp [Time] When the transition occurred
      def on_task_updated(task_class, previous_state:, current_state:, timestamp:)
        current_phase = facade&.current_phase || :run

        if current_phase == :clean
          handle_clean_event(task_class, previous_state, current_state, timestamp)
        else
          handle_run_event(task_class, previous_state, current_state, timestamp)
        end
      end

      private

      def handle_run_event(task_class, previous_state, current_state, timestamp)
        case [previous_state, current_state]
        when [:pending, :running]
          @task_start_times[[:run, task_class]] = timestamp
          log_task_started(task_class)
        when [:running, :completed]
          duration = calculate_duration(:run, task_class, timestamp)
          log_task_completed(task_class, duration)
        when [:running, :failed]
          duration = calculate_duration(:run, task_class, timestamp)
          log_task_failed(task_class, duration)
        when [:pending, :skipped]
          log_task_skipped(task_class)
        end
      end

      def handle_clean_event(task_class, previous_state, current_state, timestamp)
        case [previous_state, current_state]
        when [:pending, :running]
          @task_start_times[[:clean, task_class]] = timestamp
          log_clean_started(task_class)
        when [:running, :completed]
          duration = calculate_duration(:clean, task_class, timestamp)
          log_clean_completed(task_class, duration)
        when [:running, :failed]
          duration = calculate_duration(:clean, task_class, timestamp)
          log_clean_failed(task_class, duration)
        end
      end

      def calculate_duration(phase, task_class, end_time)
        start_time = @task_start_times[[phase, task_class]]
        return nil unless start_time

        ((end_time - start_time) * 1000).round(1)
      end

      def log_task_started(task_class)
        Logging.info(
          Events::TASK_STARTED,
          task: task_class.name
        )
      end

      def log_task_completed(task_class, duration)
        Logging.info(
          Events::TASK_COMPLETED,
          task: task_class.name,
          duration_ms: duration
        )
      end

      def log_task_failed(task_class, duration)
        # Note: error details are NOT available via notification - exceptions propagate to top level (Plan design)
        Logging.error(
          Events::TASK_FAILED,
          task: task_class.name,
          duration_ms: duration
        )
      end

      def log_task_skipped(task_class)
        Logging.debug(
          Events::TASK_SKIPPED,
          task: task_class.name
        )
      end

      def log_clean_started(task_class)
        Logging.debug(
          Events::TASK_CLEAN_STARTED,
          task: task_class.name
        )
      end

      def log_clean_completed(task_class, duration)
        Logging.debug(
          Events::TASK_CLEAN_COMPLETED,
          task: task_class.name,
          duration_ms: duration
        )
      end

      def log_clean_failed(task_class, duration)
        # Note: error details are NOT available via notification - exceptions propagate to top level (Plan design)
        Logging.warn(
          Events::TASK_CLEAN_FAILED,
          task: task_class.name,
          duration_ms: duration
        )
      end
    end
  end
end
