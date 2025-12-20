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

      def initialize(task, registry:, execution_context: nil)
        @task = task
        @registry = registry
        @execution_context = execution_context
        @result = nil
        @clean_result = nil
        @error = nil
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
      # @param error [Exception] The error that occurred
      def mark_failed(error)
        @timing = @timing&.with_end_now
        @monitor.synchronize do
          @error = error
          @state = STATE_COMPLETED
          @condition.broadcast
        end
        update_progress(:failed, error: error)
      end

      # Called by Executor after clean completes
      # @param result [Object] The result of cleanup
      def mark_clean_completed(result)
        @monitor.synchronize do
          @clean_result = result
          @clean_state = STATE_COMPLETED
          @clean_condition.broadcast
        end
      end

      # Wait until task is completed
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

      # Trigger execution via ExecutionContext or Executor and wait for completion
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

      # Trigger clean execution and wait for completion
      def trigger_clean_and_wait
        @monitor.synchronize do
          case @clean_state
          when STATE_PENDING
            @clean_state = STATE_RUNNING
            # Execute clean in a thread (clean doesn't use Producer-Consumer)
            thread = Thread.new { execute_clean }
            @registry.register_thread(thread)
            @clean_condition.wait_until { @clean_state == STATE_COMPLETED }
          when STATE_RUNNING
            @clean_condition.wait_until { @clean_state == STATE_COMPLETED }
          when STATE_COMPLETED
            # Already done
          end
        end
      end

      def execute_clean
        debug_log("Cleaning #{@task.class}...")
        result = @task.clean
        wait_for_clean_dependencies
        mark_clean_completed(result)
        debug_log("Clean #{@task.class} completed.")
      end

      def wait_for_clean_dependencies
        dependencies = @task.class.cached_dependencies
        return if dependencies.empty?

        wait_threads = dependencies.map do |dep_class|
          Thread.new { dep_class.clean }
        end
        wait_threads.each(&:join)
      end

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
