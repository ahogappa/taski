# frozen_string_literal: true

require "monitor"
require_relative "task_output_router"

module Taski
  module Execution
    # ExecutionContext manages execution state and notifies observers about execution events.
    # It decouples progress display from Executor using the observer pattern.
    #
    # == Architecture
    #
    # ExecutionContext is the central hub for execution events in the Taski framework:
    #
    #   Executor → Scheduler/WorkerPool/ExecutionContext → Observers
    #
    # - Executor coordinates the overall execution flow
    # - Scheduler manages dependency state and determines execution order
    # - WorkerPool manages worker threads that execute tasks
    # - ExecutionContext notifies observers about execution events
    #
    # == Observer Pattern
    #
    # Observers are registered using {#add_observer} and receive notifications
    # via duck-typed method dispatch. Observers should implement any subset of:
    #
    # - register_task(task_class) - Called when a task is registered
    # - update_task(task_class, state:, duration:, error:) - Called on state changes
    #   State values for run: :pending, :running, :completed, :failed
    #   State values for clean: :cleaning, :clean_completed, :clean_failed
    # - set_root_task(task_class) - Called when root task is set
    # - set_output_capture(output_capture) - Called when output capture is configured
    # - start - Called when execution starts
    # - stop - Called when execution ends
    #
    # == Thread Safety
    #
    # All observer operations are synchronized using Monitor. The output capture
    # getter is also thread-safe for access from worker threads.
    #
    # == Backward Compatibility
    #
    # TreeProgressDisplay works as an observer without any API changes.
    # Existing task code works unchanged.
    #
    # @example Registering an observer
    #   context = ExecutionContext.new
    #   context.add_observer(TreeProgressDisplay.new)
    #
    # @example Sending notifications
    #   context.notify_task_registered(MyTask)
    #   context.notify_task_started(MyTask)
    #   context.notify_task_completed(MyTask, duration: 1.5)
    class ExecutionContext
      # Thread-local key for storing the current execution context
      THREAD_LOCAL_KEY = :taski_execution_context

      # Get the current execution context for this thread.
      # @return [ExecutionContext, nil] The current context or nil if not set
      def self.current
        Thread.current[THREAD_LOCAL_KEY]
      end

      # Set the current execution context for this thread.
      # @param context [ExecutionContext, nil] The context to set
      def self.current=(context)
        Thread.current[THREAD_LOCAL_KEY] = context
      end

      ##
      # Creates a new ExecutionContext and initializes its internal synchronization and state.
      #
      # Initializes a monitor for thread-safe operations and sets up empty observer storage
      # and nil defaults for execution/clean triggers and output capture related fields.
      def initialize
        @monitor = Monitor.new
        @observers = []
        @execution_trigger = nil
        @clean_trigger = nil
        @output_capture = nil
        @original_stdout = nil
      end

      # Check if output capture is already active.
      # @return [Boolean] true if capture is active
      def output_capture_active?
        @monitor.synchronize { !@output_capture.nil? }
      end

      # Get the original stdout before output capture was set up.
      # Thread-safe accessor.
      #
      # @return [IO, nil] The original stdout or nil if not captured
      def original_stdout
        @monitor.synchronize { @original_stdout }
      end

      # Set up output capture for inline progress display.
      # Creates TaskOutputRouter and replaces $stdout.
      # Should only be called when progress display is active and not already set up.
      #
      # @param output_io [IO] The original output IO (usually $stdout)
      def setup_output_capture(output_io)
        @monitor.synchronize do
          @original_stdout = output_io
          @output_capture = TaskOutputRouter.new(@original_stdout, self)
          @output_capture.start_polling
          $stdout = @output_capture
        end

        notify_set_output_capture(@output_capture)
      end

      # Tear down output capture and restore original $stdout.
      def teardown_output_capture
        capture = nil
        @monitor.synchronize do
          return unless @original_stdout

          capture = @output_capture
          $stdout = @original_stdout
          @output_capture = nil
          @original_stdout = nil
        end
        capture&.stop_polling
      end

      # Get the current output capture instance.
      # Thread-safe accessor for worker threads.
      #
      # @return [TaskOutputRouter, nil] The output capture or nil if not set
      def output_capture
        @monitor.synchronize { @output_capture }
      end

      # Set the execution trigger callback.
      # This is used to break the circular dependency between TaskWrapper and Executor.
      # The trigger is a callable that takes (task_class, registry) and executes the task.
      #
      ##
      # Sets the execution trigger used to run tasks.
      # This stores a Proc that will be invoked with (task_class, registry) when a task is executed; setting to `nil` clears the custom trigger and restores the default execution behavior.
      # @param [Proc, nil] trigger - A callback receiving `(task_class, registry)`, or `nil` to unset the custom trigger.
      def execution_trigger=(trigger)
        @monitor.synchronize { @execution_trigger = trigger }
      end

      # Set the clean trigger callback.
      # This is used to break the circular dependency between TaskWrapper and Executor.
      # The trigger is a callable that takes (task_class, registry) and cleans the task.
      #
      ##
      # Sets the clean trigger callback used to run task cleaning operations.
      # @param [Proc, nil] trigger - The callback invoked by `trigger_clean`; `nil` clears the custom clean trigger.
      def clean_trigger=(trigger)
        @monitor.synchronize { @clean_trigger = trigger }
      end

      # Trigger execution of a task.
      # Falls back to Executor.execute if no custom trigger is set.
      #
      # @param task_class [Class] The task class to execute
      ##
      # Executes the given task class using the configured execution trigger or falls back to Executor.execute.
      # @param task_class [Class] The task class to execute.
      # @param registry [Registry] The task registry used during execution.
      def trigger_execution(task_class, registry:)
        trigger = @monitor.synchronize { @execution_trigger }
        if trigger
          trigger.call(task_class, registry)
        else
          # Fallback for backward compatibility
          Executor.execute(task_class, registry: registry, execution_context: self)
        end
      end

      # Trigger clean of a task.
      # Falls back to Executor.execute_clean if no custom trigger is set.
      #
      # @param task_class [Class] The task class to clean
      ##
      # Triggers a clean operation for the specified task class using the configured clean trigger or a backward-compatible fallback.
      # @param [Class] task_class - The task class to clean.
      # @param [Registry] registry - The task registry providing task lookup and metadata.
      # @return [Object] The result returned by the clean operation (implementation-dependent).
      def trigger_clean(task_class, registry:)
        trigger = @monitor.synchronize { @clean_trigger }
        if trigger
          trigger.call(task_class, registry)
        else
          # Fallback for backward compatibility
          Executor.execute_clean(task_class, registry: registry, execution_context: self)
        end
      end

      # Add an observer to receive execution notifications.
      # Observers should implement the following methods (all optional):
      # - register_task(task_class)
      # - update_task(task_class, state:, duration:, error:)
      # - set_root_task(task_class)
      # - set_output_capture(output_capture)
      # - start
      # - stop
      #
      # @param observer [Object] The observer to add
      def add_observer(observer)
        @monitor.synchronize { @observers << observer }
      end

      # Remove an observer.
      #
      # @param observer [Object] The observer to remove
      def remove_observer(observer)
        @monitor.synchronize { @observers.delete(observer) }
      end

      # Returns a copy of the current observers list.
      #
      # @return [Array<Object>] Copy of observers array
      def observers
        @monitor.synchronize { @observers.dup }
      end

      # Notify observers that a task has been registered.
      #
      # @param task_class [Class] The task class that was registered
      def notify_task_registered(task_class)
        dispatch(:register_task, task_class)
      end

      # Notify observers that a task has started execution.
      #
      # @param task_class [Class] The task class that started
      def notify_task_started(task_class)
        dispatch(:update_task, task_class, state: :running)
      end

      # Notify observers that a task has completed.
      #
      # @param task_class [Class] The task class that completed
      # @param duration [Float, nil] The execution duration in seconds
      # @param error [Exception, nil] The error if the task failed
      def notify_task_completed(task_class, duration: nil, error: nil)
        state = error ? :failed : :completed
        dispatch(:update_task, task_class, state: state, duration: duration, error: error)
      end

      # Notify observers that a task was skipped (never executed).
      #
      # @param task_class [Class] The task class that was skipped
      def notify_task_skipped(task_class)
        dispatch(:update_task, task_class, state: :skipped)
      end

      # Notify observers to set the root task.
      #
      # @param task_class [Class] The root task class
      def notify_set_root_task(task_class)
        dispatch(:set_root_task, task_class)
      end

      # Notify observers to set the output capture.
      #
      # @param output_capture [TaskOutputRouter] The output capture instance
      def notify_set_output_capture(output_capture)
        dispatch(:set_output_capture, output_capture)
      end

      # Notify observers to start.
      def notify_start
        dispatch(:start)
      end

      # Notify observers to stop.
      def notify_stop
        dispatch(:stop)
      end

      # ========================================
      # Clean Lifecycle Notifications
      # ========================================

      # Notify observers that a task's clean has started.
      #
      ##
      # Notifies observers that cleaning of the given task has started.
      # Dispatches an `:update_task` notification with `state: :cleaning`.
      # @param [Class] task_class The task class that started cleaning.
      def notify_clean_started(task_class)
        dispatch(:update_task, task_class, state: :cleaning)
      end

      # Notify observers that a task's clean has completed.
      #
      # @param task_class [Class] The task class that completed cleaning
      # @param duration [Float, nil] The clean duration in milliseconds
      ##
      # Notifies observers that a task's clean has completed, including duration and any error.
      # Observers receive an `:update_task` notification with `state` set to `:clean_completed` when
      # `error` is nil, or `:clean_failed` when `error` is provided.
      # @param [Class] task_class - The task class that finished cleaning.
      # @param [Numeric, nil] duration - The duration of the clean operation in milliseconds, or `nil` if unknown.
      # @param [Exception, nil] error - The error raised during cleaning, or `nil` if the clean succeeded.
      def notify_clean_completed(task_class, duration: nil, error: nil)
        state = error ? :clean_failed : :clean_completed
        dispatch(:update_task, task_class, state: state, duration: duration, error: error)
      end

      # ========================================
      # Group Lifecycle Notifications
      # ========================================

      # Notify observers that a group has started within a task.
      #
      # @param task_class [Class] The task class containing the group
      # @param group_name [String] The name of the group
      def notify_group_started(task_class, group_name)
        dispatch(:update_group, task_class, group_name, state: :running)
      end

      # Notify observers that a group has completed within a task.
      #
      # @param task_class [Class] The task class containing the group
      # @param group_name [String] The name of the group
      # @param duration [Float, nil] The group duration in milliseconds
      # @param error [Exception, nil] The error if the group failed
      def notify_group_completed(task_class, group_name, duration: nil, error: nil)
        state = error ? :failed : :completed
        dispatch(:update_group, task_class, group_name, state: state, duration: duration, error: error)
      end

      private

      # Dispatch a method call to all observers that respond to the method.
      # Uses duck typing: observers only receive calls for methods they implement.
      #
      # @param method_name [Symbol] The method to call on observers
      # @param args [Array] Arguments to pass to the method
      # @param kwargs [Hash] Keyword arguments to pass to the method
      def dispatch(method_name, *args, **kwargs)
        current_observers = @monitor.synchronize { @observers.dup }
        current_observers.each do |observer|
          next unless observer.respond_to?(method_name)

          begin
            if kwargs.empty?
              observer.public_send(method_name, *args)
            else
              observer.public_send(method_name, *args, **kwargs)
            end
          rescue => e
            warn "[ExecutionContext] Observer #{observer.class} raised error in #{method_name}: #{e.message}"
          end
        end
      end
    end
  end
end
