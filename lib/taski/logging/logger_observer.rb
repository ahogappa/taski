# frozen_string_literal: true

require_relative "../execution/task_observer"

module Taski
  module Logging
    # LoggerObserver implements the TaskObserver interface
    # to emit structured log events for task execution lifecycle.
    #
    # This observer is automatically registered when Taski.logger is set.
    #
    # @example
    #   # Internal use - automatically registered by Executor
    #   context.add_observer(LoggerObserver.new)
    class LoggerObserver < Taski::Execution::TaskObserver
      def initialize
        super
        @task_start_times = {}
      end

      # Unified event interface for task state transitions
      # @param task_class [Class] The task class
      # @param previous_state [Symbol] The previous state
      # @param current_state [Symbol] The new state
      # @param timestamp [Time] When the transition occurred
      # @param error [Exception, nil] The error if state is :failed
      def on_task_updated(task_class, previous_state:, current_state:, timestamp:, error: nil)
        current_phase = context&.current_phase || :run

        if current_phase == :clean
          handle_clean_event(task_class, previous_state, current_state, timestamp, error)
        else
          handle_run_event(task_class, previous_state, current_state, timestamp, error)
        end
      end

      private

      def handle_run_event(task_class, previous_state, current_state, timestamp, error)
        case [previous_state, current_state]
        when [:pending, :running]
          @task_start_times[[:run, task_class]] = timestamp
          log_task_started(task_class)
        when [:running, :completed]
          duration = calculate_duration(:run, task_class, timestamp)
          log_task_completed(task_class, duration)
        when [:running, :failed]
          duration = calculate_duration(:run, task_class, timestamp)
          log_task_failed(task_class, duration, error)
        when [:pending, :skipped]
          log_task_skipped(task_class)
        end
      end

      def handle_clean_event(task_class, previous_state, current_state, timestamp, error)
        case [previous_state, current_state]
        when [:pending, :running]
          @task_start_times[[:clean, task_class]] = timestamp
          log_clean_started(task_class)
        when [:running, :completed]
          duration = calculate_duration(:clean, task_class, timestamp)
          log_clean_completed(task_class, duration)
        when [:running, :failed]
          duration = calculate_duration(:clean, task_class, timestamp)
          log_clean_failed(task_class, duration, error)
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

      def log_task_failed(task_class, duration, error)
        data = {
          duration_ms: duration,
          error_class: error&.class&.name,
          message: error&.message
        }

        # Include backtrace for debugging
        data[:backtrace] = error.backtrace.first(10) if error&.backtrace

        # Include captured output if available from TaskFailure context
        # Note: captured_output is added during error aggregation in Executor

        Logging.error(
          Events::TASK_FAILED,
          task: task_class.name,
          **data
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

      def log_clean_failed(task_class, duration, error)
        Logging.warn(
          Events::TASK_CLEAN_FAILED,
          task: task_class.name,
          duration_ms: duration,
          error_class: error&.class&.name,
          message: error&.message
        )
      end
    end
  end
end
