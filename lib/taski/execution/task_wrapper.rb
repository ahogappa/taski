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

    class TaskWrapper
      attr_reader :task, :result

      STATE_PENDING = :pending
      STATE_RUNNING = :running
      STATE_COMPLETED = :completed

      def initialize(task, registry:, coordinator:)
        @task = task
        @registry = registry
        @coordinator = coordinator
        @result = nil
        @clean_result = nil
        @error = nil
        @monitor = Monitor.new
        @condition = @monitor.new_cond
        @clean_condition = @monitor.new_cond
        @state = STATE_PENDING
        @clean_state = STATE_PENDING
        @timing = nil

        register_with_progress_display
      end

      # @return [Object] The result of task execution
      def run
        execute_task_if_needed
        raise @error if @error
        @result
      end

      # @return [Object] The result of cleanup
      def clean
        execute_clean_if_needed
        @clean_result
      end

      # @param method_name [Symbol] The name of the exported method
      # @return [Object] The exported value
      def get_exported_value(method_name)
        execute_task_if_needed
        raise @error if @error
        @task.public_send(method_name)
      end

      private

      def start_thread_with(&block)
        thread = Thread.new(&block)
        @registry.register_thread(thread)
      end

      # Thread-safe state machine that ensures operations are executed exactly once.
      # Uses pattern matching for exhaustive state handling.
      def execute_with_state_pattern(state_getter:, starter:, waiter:, pre_start_check: nil)
        @monitor.synchronize do
          case state_getter.call
          in STATE_PENDING
            pre_start_check&.call
            starter.call
            waiter.call
          in STATE_RUNNING
            waiter.call
          in STATE_COMPLETED
            return
          end
        end
      end

      def execute_task_if_needed
        execute_with_state_pattern(
          state_getter: -> { @state },
          starter: -> { start_async_execution },
          waiter: -> { wait_for_completion },
          pre_start_check: -> {
            if @registry.abort_requested?
              raise Taski::TaskAbortException, "Execution aborted - no new tasks will start"
            end
          }
        )
      end

      def start_async_execution
        @state = STATE_RUNNING
        @timing = TaskTiming.start_now
        update_progress(:running)
        start_thread_with { execute_task }
      end

      def execute_task
        if @registry.abort_requested?
          @error = Taski::TaskAbortException.new("Execution aborted - no new tasks will start")
          mark_completed
          return
        end

        log_start
        @coordinator.start_dependencies(@task.class)
        wait_for_dependencies
        @result = @task.run
        mark_completed
        log_completion
      rescue Taski::TaskAbortException => e
        @registry.request_abort!
        @error = e
        mark_completed
      rescue => e
        @error = e
        mark_completed
      end

      def wait_for_dependencies
        dependencies = @task.class.cached_dependencies
        return if dependencies.empty?

        dependencies.each do |dep_class|
          dep_class.exported_methods.each do |method|
            dep_class.public_send(method)
          end
        end
      end

      def execute_clean_if_needed
        execute_with_state_pattern(
          state_getter: -> { @clean_state },
          starter: -> { start_async_clean },
          waiter: -> { wait_for_clean_completion }
        )
      end

      def start_async_clean
        @clean_state = STATE_RUNNING
        start_thread_with { execute_clean }
      end

      def execute_clean
        log_clean_start
        @clean_result = @task.clean
        wait_for_clean_dependencies
        mark_clean_completed
        log_clean_completion
      end

      def wait_for_clean_dependencies
        dependencies = @task.class.cached_dependencies
        return if dependencies.empty?

        wait_threads = dependencies.map do |dep_class|
          Thread.new do
            dep_class.public_send(:clean)
          end
        end

        wait_threads.each(&:join)
      end

      def mark_completed
        @timing = @timing&.with_end_now
        @monitor.synchronize do
          @state = STATE_COMPLETED
          @condition.broadcast
        end

        if @error
          update_progress(:failed, error: @error)
        else
          update_progress(:completed, duration: @timing&.duration_ms)
        end
      end

      def mark_clean_completed
        @monitor.synchronize do
          @clean_state = STATE_COMPLETED
          @clean_condition.broadcast
        end
      end

      def wait_for_completion
        @condition.wait_until { @state == STATE_COMPLETED }
      end

      def wait_for_clean_completion
        @clean_condition.wait_until { @clean_state == STATE_COMPLETED }
      end

      def debug_log(message)
        return unless ENV["TASKI_DEBUG"]
        puts message
      end

      def log_start
        debug_log("Invoking #{@task.class} wrapper in thread #{Thread.current.object_id}...")
      end

      def log_completion
        debug_log("Wrapper #{@task.class} completed in thread #{Thread.current.object_id}.")
      end

      def log_clean_start
        debug_log("Cleaning #{@task.class} in thread #{Thread.current.object_id}...")
      end

      def log_clean_completion
        debug_log("Clean #{@task.class} completed in thread #{Thread.current.object_id}.")
      end

      def register_with_progress_display
        Taski.progress_display&.register_task(@task.class)
      end

      # @param state [Symbol] The new state
      # @param duration [Float, nil] Duration in milliseconds
      # @param error [Exception, nil] Error object
      def update_progress(state, duration: nil, error: nil)
        Taski.progress_display&.update_task(@task.class, state: state, duration: duration, error: error)
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
    end
  end
end
