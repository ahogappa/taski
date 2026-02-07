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
    # TaskWrapper does NOT start threads or fibers — the Executor and
    # WorkerPool control all scheduling and execution.
    class TaskWrapper
      attr_reader :task, :result, :error, :timing, :clean_error

      STATE_PENDING = :pending
      STATE_RUNNING = :running
      STATE_COMPLETED = :completed

      ##
      # Create a new TaskWrapper for the given task and registry.
      # Initializes synchronization primitives, state tracking for execution and cleanup, and timing/result/error holders.
      # @param [Object] task - The task instance being wrapped.
      # @param [Object] registry - The registry used to query abort status and coordinate execution.
      # @param [Object, nil] execution_context - Optional execution context used to trigger and report execution and cleanup.
      # @param [Hash, nil] args - User-defined arguments for Task.new usage.
      def initialize(task, registry:, execution_context: nil, args: nil)
        @task = task
        @registry = registry
        @execution_context = execution_context
        @args = args
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
        @clean_timing = nil
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

      # Resets the wrapper state to allow re-execution.
      # Clears all cached results and returns state to pending.
      def reset!
        @monitor.synchronize do
          @state = STATE_PENDING
          @clean_state = STATE_PENDING
          @result = nil
          @clean_result = nil
          @error = nil
          @clean_error = nil
          @timing = nil
          @clean_timing = nil
        end
        @task.reset! if @task.respond_to?(:reset!)
        @registry.reset!
      end

      # Called by user code to get result. Triggers execution if needed.
      # Sets up args if not already set (for Task.new.run usage).
      # @return [Object] The result of task execution
      def run
        with_args_lifecycle do
          trigger_execution_and_wait
          raise @error if @error # steep:ignore
          @result
        end
      end

      # Called by user code to clean. Triggers clean execution if needed.
      # Sets up args if not already set (for Task.new.clean usage).
      # @return [Object] The result of cleanup
      def clean
        with_args_lifecycle do
          trigger_clean_and_wait
          @clean_result
        end
      end

      # Called by user code to run and clean. Runs execution followed by cleanup.
      # If run fails, clean is still executed for resource release.
      # An optional block is executed between run and clean phases.
      # Pre-increments progress display nest_level to prevent double rendering.
      # @param block [Proc, nil] Optional block executed between run and clean
      # @return [Object] The result of task execution
      def run_and_clean(&block)
        context = ensure_execution_context
        context.notify_start # Pre-increment nest_level to prevent double rendering
        result = run
        block&.call
        result
      ensure
        clean
        context&.notify_stop # Final decrement and render
      end

      # Called by user code to get exported value. Triggers execution if needed.
      # Sets up args if not already set (for Task.new usage).
      # @param method_name [Symbol] The name of the exported method
      # @return [Object] The exported value
      def get_exported_value(method_name)
        with_args_lifecycle do
          trigger_execution_and_wait
          raise @error if @error # steep:ignore
          @task.public_send(method_name)
        end
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
      # Mark the task's cleanup state as running and start timing.
      # @return [Boolean] `true` if the clean state was changed from pending to running, `false` otherwise.
      def mark_clean_running
        @monitor.synchronize do
          return false unless @clean_state == STATE_PENDING
          @clean_state = STATE_RUNNING
          @clean_timing = TaskTiming.start_now
          true
        end
      end

      # Called by Executor after clean completes
      ##
      # Marks the cleanup run as completed, stores the cleanup result, sets the clean state to COMPLETED,
      # notifies any waiters, and reports completion to observers.
      # @param [Object] result - The result of the cleanup operation.
      def mark_clean_completed(result)
        @clean_timing = @clean_timing&.with_end_now
        @monitor.synchronize do
          @clean_result = result
          @clean_state = STATE_COMPLETED
          @clean_condition.broadcast
        end
        update_clean_progress(:clean_completed, duration: @clean_timing&.duration_ms)
      end

      # Called by Executor when clean raises an error
      ##
      # Marks the cleanup as failed by storing the cleanup error, transitioning the cleanup state to completed,
      # notifying any waiters, and reports failure to observers.
      # @param [Exception] error - The exception raised during the cleanup run.
      def mark_clean_failed(error)
        @clean_timing = @clean_timing&.with_end_now
        @monitor.synchronize do
          @clean_error = error
          @clean_state = STATE_COMPLETED
          @clean_condition.broadcast
        end
        update_clean_progress(:clean_failed, duration: @clean_timing&.duration_ms, error: error)
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

      ##
      # Blocks the current thread until the task's clean phase reaches the completed state.
      # The caller will be suspended until the wrapper's clean_state becomes STATE_COMPLETED.
      def wait_for_clean_completion
        @monitor.synchronize do
          @clean_condition.wait_until { @clean_state == STATE_COMPLETED }
        end
      end

      ##
      # Delegates method calls to get_exported_value for exported task methods.
      # @param method_name [Symbol] The method name being called.
      # @param args [Array] Arguments passed to the method.
      # @param block [Proc] Block passed to the method.
      # @return [Object] The exported value for the method.
      def method_missing(method_name, *args, &block)
        if @task.class.method_defined?(method_name)
          get_exported_value(method_name)
        else
          super
        end
      end

      ##
      # Returns true if the task class defines the given method.
      # @param method_name [Symbol] The method name to check.
      # @param include_private [Boolean] Whether to include private methods.
      # @return [Boolean] true if the task responds to the method.
      def respond_to_missing?(method_name, include_private = false)
        @task.class.method_defined?(method_name) || super
      end

      private

      ##
      # Ensures args are set during block execution, then resets if they weren't set before.
      # This allows Task.new.run usage without requiring explicit args setup.
      # If args are already set (e.g., from Task.run class method), just yields the block.
      # Uses stored @args if set (from Task.new), otherwise uses empty hash.
      # @yield The block to execute with args lifecycle management
      # @return [Object] The result of the block
      def with_args_lifecycle(&block)
        # If args are already set, just execute the block
        return yield if Taski.args

        options = @args || {}
        Taski.send(:with_env, root_task: @task.class) do
          Taski.send(:with_args, options: options, &block)
        end
      end

      ##
      # Ensures the task is executed if still pending and waits for completion.
      # If the task is pending, triggers execution (via the configured ExecutionContext when present, otherwise via Executor) outside the monitor; if the task is running, waits until it becomes completed; if already completed, returns immediately.
      # @raise [Taski::TaskAbortException] If the registry requested an abort before execution begins.
      def trigger_execution_and_wait
        trigger_and_wait(
          state_accessor: -> { @state },
          condition: @condition,
          trigger: ->(ctx) { ctx.trigger_execution(@task.class, registry: @registry) }
        )
      end

      ##
      # Triggers task cleanup through the configured execution mechanism and waits until the cleanup completes.
      #
      # If an ExecutionContext is configured the cleanup is invoked through it; otherwise a fallback executor is used.
      # @raise [Taski::TaskAbortException] if the registry has requested an abort.
      def trigger_clean_and_wait
        trigger_and_wait(
          state_accessor: -> { @clean_state },
          condition: @clean_condition,
          trigger: ->(ctx) { ctx.trigger_clean(@task.class, registry: @registry) }
        )
      end

      # Generic trigger-and-wait implementation for both run and clean phases.
      # @param state_accessor [Proc] Lambda returning the current state
      # @param condition [MonitorMixin::ConditionVariable] Condition to wait on
      # @param trigger [Proc] Lambda receiving context to trigger execution
      # @raise [Taski::TaskAbortException] If the registry requested an abort
      def trigger_and_wait(state_accessor:, condition:, trigger:)
        should_execute = false
        @monitor.synchronize do
          case state_accessor.call
          when STATE_PENDING
            check_abort!
            should_execute = true
          when STATE_RUNNING
            condition.wait_until { state_accessor.call == STATE_COMPLETED }
          when STATE_COMPLETED
            # Already done
          end
        end

        if should_execute
          # Execute outside the lock to avoid deadlock
          context = ensure_execution_context
          trigger.call(context)
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

      ##
      # Ensures an execution context exists for this wrapper.
      # Returns the existing context if set, otherwise creates a shared context.
      # This enables run and clean phases to share state like runtime dependencies.
      # @return [ExecutionContext] The execution context for this wrapper
      def ensure_execution_context
        @execution_context ||= create_shared_context
      end

      ##
      # Creates a shared execution context with proper triggers for run and clean.
      # The context is configured to reuse itself when triggering nested executions.
      # @return [ExecutionContext] A new execution context
      def create_shared_context
        context = ExecutionContext.new
        progress = Taski.progress_display
        context.add_observer(progress) if progress

        # Add logger observer if logging is enabled
        if Taski.logger
          context.add_observer(Taski::Logging::LoggerObserver.new)
        end

        # Set triggers to reuse this context for nested executions
        context.execution_trigger = ->(task_class, registry) do
          Executor.execute(task_class, registry: registry, execution_context: context)
        end
        context.clean_trigger = ->(task_class, registry) do
          Executor.execute_clean(task_class, registry: registry, execution_context: context)
        end

        context
      end

      ##
      # Notifies the execution context of task completion or failure.
      # Falls back to getting the current context if not set during initialization.
      # @param state [Symbol] The completion state (unused, kept for API consistency).
      # @param duration [Numeric, nil] The execution duration in milliseconds.
      # @param error [Exception, nil] The error if the task failed.
      def update_progress(state, duration: nil, error: nil)
        # Defensive fallback: try to get current context if not set during initialization
        @execution_context ||= ExecutionContext.current
        return unless @execution_context

        @execution_context.notify_task_completed(@task.class, duration: duration, error: error)
      end

      ##
      # Notifies the execution context of clean completion or failure.
      # Falls back to getting the current context if not set during initialization.
      # @param state [Symbol] The clean state (unused, kept for API consistency).
      # @param duration [Numeric, nil] The clean duration in milliseconds.
      # @param error [Exception, nil] The error if the clean failed.
      def update_clean_progress(state, duration: nil, error: nil)
        # Defensive fallback: try to get current context if not set during initialization
        @execution_context ||= ExecutionContext.current
        return unless @execution_context

        @execution_context.notify_clean_completed(@task.class, duration: duration, error: error)
      end

      ##
      # Outputs a debug message if TASKI_DEBUG environment variable is set.
      # @param message [String] The debug message to output.
      def debug_log(message)
        return unless ENV["TASKI_DEBUG"]
        puts "[TaskWrapper] #{message}"
      end
    end
  end
end
