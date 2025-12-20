# frozen_string_literal: true

require "monitor"

module Taski
  module Execution
    class TaskTiming < Data.define(:start_time, :end_time)
      # @return [Float, nil] Duration in milliseconds or nil if not available
      def duration_ms
        return nil unless start_time && end_time
        ((end_time - start_time) * 1000).round(1)
      end

      # @return [TaskTiming] New timing with current time as start
      def self.start_now
        new(start_time: Time.now, end_time: nil)
      end

      # @return [TaskTiming] New timing with current time as end
      def with_end_now
        with(end_time: Time.now)
      end
    end

    # TaskWrapper manages the state and synchronization for a single task.
    # In the Producer-Consumer pattern, TaskWrapper does NOT start threads.
    # The Executor controls all scheduling and execution.
    class TaskWrapper
      attr_reader :task, :result, :error, :timing

      STATE_PENDING = :pending
      STATE_RUNNING = :running
      STATE_COMPLETED = :completed

      ##
      # Create a new TaskWrapper for the given task and registry.
      # Initializes synchronization primitives, state tracking for execution and cleanup, and timing/result/error holders.
      # @param [Object] task - The task instance being wrapped.
      # @param [Object] registry - The registry used to query abort status and coordinate execution.
      # @param [Object, nil] execution_context - Optional execution context used to trigger and report execution and cleanup.
      def initialize(task, registry:, execution_context: nil)
        @task = task
        @registry = registry
        @execution_context = execution_context
        @result = nil
        @clean_result = nil
        @error = nil
        @clean_error = nil
        @monitor = Monitor.new
        @condition = @monitor.new_cond
        @clean_condition = @monitor.new_cond
        @state = STATE_PENDING
        @clean_state = STATE_PENDING
        @timing = nil
      end

      # @return [Symbol] Current state
      def state
        @monitor.synchronize { @state }
      end

      # @return [Boolean] true if task is pending
      def pending?
        state == STATE_PENDING
      end

      # @return [Boolean] true if task is completed
      def completed?
        state == STATE_COMPLETED
      end

      # Called by user code to get result. Triggers execution if needed.
      # @return [Object] The result of task execution
      def run
        trigger_execution_and_wait
        raise @error if @error # steep:ignore
        @result
      end

      # Called by user code to clean. Triggers clean execution if needed.
      # @return [Object] The result of cleanup
      def clean
        trigger_clean_and_wait
        @clean_result
      end

      # Called by user code to get exported value. Triggers execution if needed.
      # @param method_name [Symbol] The name of the exported method
      # @return [Object] The exported value
      def get_exported_value(method_name)
        trigger_execution_and_wait
        raise @error if @error # steep:ignore
        @task.public_send(method_name)
      end

      # Called by Executor to mark task as running
      def mark_running
        @monitor.synchronize do
          return false unless @state == STATE_PENDING
          @state = STATE_RUNNING
          @timing = TaskTiming.start_now
          true
        end
      end

      # Called by Executor after task.run completes successfully
      # @param result [Object] The result of task execution
      def mark_completed(result)
        @timing = @timing&.with_end_now
        @monitor.synchronize do
          @result = result
          @state = STATE_COMPLETED
          @condition.broadcast
        end
        update_progress(:completed, duration: @timing&.duration_ms)
      end

      # Called by Executor when task.run raises an error
      ##
      # Marks the task as failed and records the error.
      # Records the provided error, sets the task state to completed, updates the timing end time, notifies threads waiting for completion, and reports the failure to the execution context.
      # @param [Exception] error - The exception raised during task execution.
      def mark_failed(error)
        @timing = @timing&.with_end_now
        @monitor.synchronize do
          @error = error
          @state = STATE_COMPLETED
          @condition.broadcast
        end
        update_progress(:failed, error: error)
      end

      # Called by Executor to mark clean as running
      ##
      # Mark the task's cleanup state as running.
      # @return [Boolean] `true` if the clean state was changed from pending to running, `false` otherwise.
      def mark_clean_running
        @monitor.synchronize do
          return false unless @clean_state == STATE_PENDING
          @clean_state = STATE_RUNNING
          true
        end
      end

      # Called by Executor after clean completes
      ##
      # Marks the cleanup run as completed, stores the cleanup result, sets the clean state to COMPLETED, and notifies any waiters.
      # @param [Object] result - The result of the cleanup operation.
      def mark_clean_completed(result)
        @monitor.synchronize do
          @clean_result = result
          @clean_state = STATE_COMPLETED
          @clean_condition.broadcast
        end
      end

      # Called by Executor when clean raises an error
      ##
      # Marks the cleanup as failed by storing the cleanup error, transitioning the cleanup state to completed, and notifying any waiters.
      # @param [Exception] error - The exception raised during the cleanup run.
      def mark_clean_failed(error)
        @monitor.synchronize do
          @clean_error = error
          @clean_state = STATE_COMPLETED
          @clean_condition.broadcast
        end
      end

      ##
      # Blocks the current thread until the task reaches the completed state.
      #
      # The caller will be suspended until the wrapper's state becomes STATE_COMPLETED.
      # This method does not raise on its own; any errors from task execution are surfaced elsewhere.
      def wait_for_completion
        @monitor.synchronize do
          @condition.wait_until { @state == STATE_COMPLETED }
        end
      end

      # Wait until clean is completed
      def wait_for_clean_completion
        @monitor.synchronize do
          @clean_condition.wait_until { @clean_state == STATE_COMPLETED }
        end
      end

      def method_missing(method_name, *args, &block)
        if @task.class.method_defined?(method_name)
          get_exported_value(method_name)
        else
          super
        end
      end

      def respond_to_missing?(method_name, include_private = false)
        @task.class.method_defined?(method_name) || super
      end

      private

      ##
      # Ensures the task is executed if still pending and waits for completion.
      # If the task is pending, triggers execution (via the configured ExecutionContext when present, otherwise via Executor) outside the monitor; if the task is running, waits until it becomes completed; if already completed, returns immediately.
      # @raise [Taski::TaskAbortException] If the registry requested an abort before execution begins.
      def trigger_execution_and_wait
        should_execute = false
        @monitor.synchronize do
          case @state
          when STATE_PENDING
            check_abort!
            should_execute = true
          when STATE_RUNNING
            @condition.wait_until { @state == STATE_COMPLETED }
          when STATE_COMPLETED
            # Already done
          end
        end

        if should_execute
          # Execute outside the lock to avoid deadlock
          if @execution_context
            @execution_context.trigger_execution(@task.class, registry: @registry)
          else
            # Fallback for backward compatibility
            Executor.execute(@task.class, registry: @registry)
          end
          # After execution returns, the task is completed
        end
      end

      ##
      # Triggers task cleanup through the configured execution mechanism and waits until the cleanup completes.
      #
      # If an ExecutionContext is configured the cleanup is invoked through it; otherwise a fallback executor is used.
      # @raise [Taski::TaskAbortException] if the registry has requested an abort.
      def trigger_clean_and_wait
        should_execute = false
        @monitor.synchronize do
          case @clean_state
          when STATE_PENDING
            check_abort!
            should_execute = true
          when STATE_RUNNING
            @clean_condition.wait_until { @clean_state == STATE_COMPLETED }
          when STATE_COMPLETED
            # Already done
          end
        end

        if should_execute
          # Execute outside the lock to avoid deadlock
          if @execution_context
            @execution_context.trigger_clean(@task.class, registry: @registry)
          else
            # Fallback for backward compatibility
            Executor.execute_clean(@task.class, registry: @registry)
          end
          # After execution returns, the task is completed
        end
      end

      ##
      # Checks whether the registry has requested an abort and raises an exception to stop starting new tasks.
      # @raise [Taski::TaskAbortException] if `@registry.abort_requested?` is true — raised with the message "Execution aborted - no new tasks will start".
      def check_abort!
        if @registry.abort_requested?
          raise Taski::TaskAbortException, "Execution aborted - no new tasks will start"
        end
      end

      def update_progress(state, duration: nil, error: nil)
        # Defensive fallback: try to get current context if not set during initialization
        @execution_context ||= ExecutionContext.current
        return unless @execution_context

        @execution_context.notify_task_completed(@task.class, duration: duration, error: error)
      end

      def debug_log(message)
        return unless ENV["TASKI_DEBUG"]
        puts "[TaskWrapper] #{message}"
      end
    end
  end
end
