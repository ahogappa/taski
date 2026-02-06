# frozen_string_literal: true

module Taski
  module Logging
    # LoggerObserver implements the ExecutionContext observer interface
    # to emit structured log events for task execution lifecycle.
    #
    # This observer is automatically registered when Taski.logger is set.
    #
    # @example
    #   # Internal use - automatically registered by Executor
    #   context.add_observer(LoggerObserver.new)
    class LoggerObserver
      # Called when a task starts execution
      # @param task_class [Class] The task class that started
      # @param state [Symbol] The state (:running)
      # @param duration [Float, nil] Duration (nil for start events)
      # @param error [Exception, nil] Error (nil for start events)
      def update_task(task_class, state:, duration: nil, error: nil)
        case state
        when :running
          log_task_started(task_class)
        when :completed
          log_task_completed(task_class, duration)
        when :failed
          log_task_failed(task_class, duration, error)
        when :skipped
          log_task_skipped(task_class)
        when :cleaning
          log_clean_started(task_class)
        when :clean_completed
          log_clean_completed(task_class, duration)
        when :clean_failed
          log_clean_failed(task_class, duration, error)
        end
      end

      private

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
        if error&.backtrace
          data[:backtrace] = error.backtrace.first(10)
        end

        # Include captured output if available from TaskFailure context
        # Note: captured_output is added during error aggregation in Executor

        Logging.error(
          Events::TASK_FAILED,
          task: task_class.name,
          **data
        )
      end

      def log_task_skipped(task_class)
        Logging.info(
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
