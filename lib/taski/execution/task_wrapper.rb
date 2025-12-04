# frozen_string_literal: true

require "monitor"

module Taski
  module Execution
    # Wrapper for task execution with parallel dependency resolution and state management
    class TaskWrapper
      attr_reader :task, :result

      # Execution states
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
        @start_time = nil
        @end_time = nil

        # Register with progress display if enabled
        register_with_progress_display
      end

      # Execute the task and return the result
      #
      # @return [Object] The result of task execution
      def run
        execute_task_if_needed
        raise @error if @error
        @result
      end

      # Clean the task (executes in reverse dependency order)
      #
      # @return [Object] The result of cleanup
      def clean
        execute_clean_if_needed
        @clean_result
      end

      # Get an exported value from the task
      # This method is used to access exported values defined by the task
      #
      # @param method_name [Symbol] The name of the exported method
      # @return [Object] The exported value
      def get_exported_value(method_name)
        execute_task_if_needed
        raise @error if @error
        @task.public_send(method_name)
      end

      private

      # Start a new thread and register it with the registry
      #
      # @yield Block to execute in the thread
      def start_thread_with(&block)
        thread = Thread.new(&block)
        @registry.register_thread(thread)
      end

      # Common pattern for executing operations with state management
      #
      # This method implements a thread-safe state machine that ensures
      # operations are executed exactly once even with concurrent access.
      #
      # @param state_getter [Proc] Proc that returns current state
      # @param starter [Proc] Proc that starts the operation
      # @param waiter [Proc] Proc that waits for completion
      # @param pre_start_check [Proc, nil] Optional check before starting
      def execute_with_state_pattern(state_getter:, starter:, waiter:, pre_start_check: nil)
        @monitor.synchronize do
          current_state = state_getter.call

          case current_state
          when STATE_PENDING
            pre_start_check&.call
            starter.call
            waiter.call
          when STATE_RUNNING
            waiter.call
          when STATE_COMPLETED
            return
          else
            raise "Unknown state: #{current_state}"
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
        @start_time = Time.now
        update_progress(:running)
        start_thread_with { execute_task }
      end

      def execute_task
        # Double-check abort flag at the start of execution
        # This prevents race conditions between checking and starting
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
        # Request graceful shutdown: no new tasks will start
        @registry.request_abort!
        @error = e
        mark_completed
      rescue => e
        @error = e
        mark_completed
      end

      def wait_for_dependencies
        # Wait for all dependencies to complete by accessing their values
        dependencies = @task.class.cached_dependencies
        return if dependencies.empty?

        dependencies.each do |dep_class|
          dep_class.exported_methods.each do |method|
            # Accessing the value ensures the dependency is executed and completed
            # NOTE: Using public_send is unavoidable here for accessing dynamic exported methods
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
        # Execute clean in REVERSE order: self first, then dependencies
        @clean_result = @task.clean
        # Wait for all dependency cleans to complete (they start in parallel)
        wait_for_clean_dependencies
        mark_clean_completed
        log_clean_completion
      end

      def wait_for_clean_dependencies
        # Wait for all dependencies to complete cleanup
        # This ensures dependencies complete before we mark ourselves as completed
        dependencies = @task.class.cached_dependencies
        return if dependencies.empty?

        # Dependencies are already started by coordinator.start_clean_dependencies
        # We need to wait for all of them to complete
        # Call clean on each in parallel to ensure they all progress simultaneously
        wait_threads = dependencies.map do |dep_class|
          Thread.new do
            # NOTE: Using public_send is unavoidable for accessing dynamic clean method
            dep_class.public_send(:clean)
          end
        end

        # Wait for all dependency cleans to complete
        wait_threads.each(&:join)
      end

      def mark_completed
        @end_time = Time.now
        @monitor.synchronize do
          @state = STATE_COMPLETED
          @condition.broadcast
        end

        # Update progress display
        if @error
          update_progress(:failed, error: @error)
        else
          duration = calculate_duration
          update_progress(:completed, duration: duration)
        end
      end

      # Calculate task duration in milliseconds
      #
      # @return [Float, nil] Duration in milliseconds or nil if not available
      def calculate_duration
        return nil unless @start_time && @end_time
        ((@end_time - @start_time) * 1000).round(1)
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

      # Log a debug message if TASKI_DEBUG is enabled
      #
      # @param message [String] The message to log
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

      # Register this task with the progress display
      def register_with_progress_display
        Taski.progress_display&.register_task(@task.class)
      end

      # Update progress display
      #
      # @param state [Symbol] The new state
      # @param duration [Float, nil] Duration in milliseconds
      # @param error [Exception, nil] Error object
      def update_progress(state, duration: nil, error: nil)
        Taski.progress_display&.update_task(@task.class, state: state, duration: duration, error: error)
      end

      # Forward method calls to the task instance
      # NOTE: Using public_send here is unavoidable for method delegation pattern.
      # We need to dynamically forward unknown method calls to the wrapped task.
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
