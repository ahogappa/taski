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
    # - register_section_impl(section_class, impl_class) - Called on section impl selection
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

      def initialize
        @monitor = Monitor.new
        @observers = []
        @execution_trigger = nil
        @output_capture = nil
        @original_stdout = nil
      end

      # Set up output capture for inline progress display.
      # Only sets up capture if $stdout is a TTY.
      # Creates TaskOutputRouter and replaces $stdout.
      #
      # @param output_io [IO] The original output IO (usually $stdout)
      def setup_output_capture(output_io)
        return unless output_io.tty?

        @monitor.synchronize do
          @original_stdout = output_io
          @output_capture = TaskOutputRouter.new(@original_stdout)
        end

        $stdout = @output_capture
        notify_set_output_capture(@output_capture)
      end

      # Tear down output capture and restore original $stdout.
      def teardown_output_capture
        original = @monitor.synchronize { @original_stdout }
        return unless original

        $stdout = original

        @monitor.synchronize do
          @output_capture = nil
          @original_stdout = nil
        end
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
      # @param trigger [Proc, nil] The execution trigger callback
      def execution_trigger=(trigger)
        @monitor.synchronize { @execution_trigger = trigger }
      end

      # Trigger execution of a task.
      # Falls back to Executor.execute if no custom trigger is set.
      #
      # @param task_class [Class] The task class to execute
      # @param registry [Registry] The task registry
      def trigger_execution(task_class, registry:)
        trigger = @monitor.synchronize { @execution_trigger }
        if trigger
          trigger.call(task_class, registry)
        else
          # Fallback for backward compatibility
          Executor.execute(task_class, registry: registry)
        end
      end

      # Add an observer to receive execution notifications.
      # Observers should implement the following methods (all optional):
      # - register_task(task_class)
      # - update_task(task_class, state:, duration:, error:)
      # - register_section_impl(section_class, impl_class)
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

      # Notify observers that a section implementation has been selected.
      #
      # @param section_class [Class] The section class
      # @param impl_class [Class] The selected implementation class
      def notify_section_impl_selected(section_class, impl_class)
        dispatch(:register_section_impl, section_class, impl_class)
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

          if kwargs.empty?
            observer.public_send(method_name, *args)
          else
            observer.public_send(method_name, *args, **kwargs)
          end
        end
      end
    end
  end
end
