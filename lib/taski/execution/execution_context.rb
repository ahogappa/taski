# frozen_string_literal: true

require "monitor"
require_relative "task_output_router"
require_relative "task_observer"

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
    # == Observer Pattern (Unified Events)
    #
    # Observers are registered using {#add_observer} and receive notifications
    # via duck-typed method dispatch. The unified event system consists of 8 events:
    #
    # === Lifecycle Events (3)
    # - on_ready - Called when execution is ready (root task and dependencies resolved)
    # - start - Called when execution starts
    # - stop - Called when execution ends
    #
    # === Phase Events (2)
    # - on_phase_started(phase) - Called when a phase starts (:run or :clean)
    # - on_phase_completed(phase) - Called when a phase completes
    #
    # === Task Events (1)
    # - on_task_updated(task_class, previous_state:, current_state:, timestamp:, error:)
    #   Called on state transitions. Unified state values for both run and clean phases:
    #   :pending, :running, :completed, :failed, :skipped
    #
    # === Group Events (2)
    # - on_group_started(task_class, group_name) - Called when a group starts
    # - on_group_completed(task_class, group_name) - Called when a group completes
    #
    # == Pull API
    #
    # Observers can access additional information via the Pull API:
    # - context.current_phase - Current phase (:run or :clean)
    # - context.root_task_class - The root task class
    # - context.dependency_graph - Static dependency graph
    # - context.output_stream - Captured output (TaskOutputRouter)
    #
    # == Thread Safety
    #
    # All observer operations are synchronized using Monitor. The output capture
    # getter is also thread-safe for access from worker threads.
    #
    # == Execution Order
    #
    # Events are dispatched in this order:
    #   ready → start → phase_started(:run) → task_updated... →
    #   phase_completed(:run) → phase_started(:clean) → task_updated... →
    #   phase_completed(:clean) → stop
    #
    # == Push vs Pull
    #
    # Events push minimal identifiers (task_class, state transitions).
    # Observers pull detailed information from context as needed:
    # - dependency_graph for task relationships
    # - output_stream.read(task_class) for captured output
    # - current_phase to distinguish run vs clean
    #
    # == Legacy Observer Methods
    #
    # For backward compatibility, the following legacy methods are still dispatched:
    # - set_root_task(task_class) - Called when root task is set
    # - start / stop - Called when execution starts/ends
    #
    # @example Registering an observer
    #   context = ExecutionContext.new
    #   context.add_observer(MyObserver.new)
    #
    # @example Using Pull API in observer
    #   class MyObserver < TaskObserver
    #     def on_ready
    #       @graph = context.dependency_graph
    #       @root = context.root_task_class
    #     end
    #   end
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
        @runtime_dependencies = {}

        # Phase 2: Pull API state
        @current_phase = nil
        @root_task_class = nil
        @dependency_graph = nil
      end

      # ========================================
      # Pull API (Phase 2)
      # ========================================

      # Current execution phase (:run or :clean)
      # @return [Symbol, nil] The current phase or nil if not set
      attr_accessor :current_phase

      # The root task class being executed
      # @return [Class, nil] The root task class or nil if not set
      attr_accessor :root_task_class

      # Static dependency graph for the execution
      # @return [StaticAnalysis::DependencyGraph, nil] The dependency graph or nil if not set
      attr_accessor :dependency_graph

      # Get the output stream (OutputHub) for captured output
      # Alias for output_capture, provides Pull API naming consistency
      # @return [TaskOutputRouter, nil] The output stream or nil if not capturing
      def output_stream
        @monitor.synchronize { @output_capture }
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
        # Observers can access output via context.output_stream (Pull API)
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

      # ========================================
      # Runtime Dependency Tracking
      # ========================================

      # Register a runtime dependency between task classes.
      # Used by Section to track dynamically selected implementations.
      # Thread-safe for access from worker threads.
      #
      # @param from_class [Class] The task class that depends on to_class
      # @param to_class [Class] The dependency task class
      def register_runtime_dependency(from_class, to_class)
        @monitor.synchronize do
          @runtime_dependencies[from_class] ||= Set.new
          @runtime_dependencies[from_class].add(to_class)
        end
      end

      # Get a copy of the runtime dependencies.
      # Returns a hash mapping from_class to Set of to_classes.
      # Thread-safe accessor.
      #
      # @return [Hash{Class => Set<Class>}] Copy of runtime dependencies
      def runtime_dependencies
        @monitor.synchronize do
          @runtime_dependencies.transform_values(&:dup)
        end
      end

      # Add an observer to receive execution notifications.
      #
      # Observers should extend TaskObserver or implement the unified event methods:
      # - on_ready - Called when execution is ready
      # - on_start - Called when execution starts
      # - on_stop - Called when execution ends
      # - on_phase_started(phase) - Called when a phase starts
      # - on_phase_completed(phase) - Called when a phase completes
      # - on_task_updated(task_class, previous_state:, current_state:, timestamp:, error:)
      # - on_group_started(task_class, group_name)
      # - on_group_completed(task_class, group_name)
      #
      # Legacy methods are also supported for backward compatibility:
      # - set_root_task(task_class)
      # - start / stop
      #
      # Observers can access Pull API via context attribute.
      #
      # @param observer [Object] The observer to add
      def add_observer(observer)
        # Inject context for TaskObserver subclasses (Pull API support)
        observer.context = self if observer.respond_to?(:context=)
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

      # Notify observers to set the root task and store for Pull API.
      #
      # @param task_class [Class] The root task class
      def notify_set_root_task(task_class)
        @root_task_class = task_class
        dispatch(:set_root_task, task_class)
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
      # Group Lifecycle Notifications
      # ========================================

      # Notify observers that a group has started within a task.
      #
      # @param task_class [Class] The task class containing the group
      # @param group_name [String] The name of the group
      def notify_group_started(task_class, group_name)
        dispatch(:on_group_started, task_class, group_name)
      end

      # Notify observers that a group has completed within a task.
      #
      # @param task_class [Class] The task class containing the group
      # @param group_name [String] The name of the group
      def notify_group_completed(task_class, group_name)
        dispatch(:on_group_completed, task_class, group_name)
      end

      # ========================================
      # New Unified Events (Phase 3)
      # ========================================

      # Notify observers that execution is ready.
      # Called when root task and dependencies have been resolved.
      # Observers can pull initial state from context in on_ready.
      def notify_ready
        dispatch(:on_ready)
      end

      # Notify observers that a phase has started.
      # @param phase [Symbol] :run or :clean
      def notify_phase_started(phase)
        dispatch(:on_phase_started, phase)
      end

      # Notify observers that a phase has completed.
      # @param phase [Symbol] :run or :clean
      def notify_phase_completed(phase)
        dispatch(:on_phase_completed, phase)
      end

      # Notify observers of a task state transition.
      # @param task_class [Class] The task class
      # @param previous_state [Symbol] The previous state
      # @param current_state [Symbol] The new state
      # @param timestamp [Time] When the transition occurred
      # @param error [Exception, nil] The error if state is :failed
      def notify_task_updated(task_class, previous_state:, current_state:, timestamp: Time.now, error: nil)
        dispatch(:on_task_updated, task_class,
          previous_state: previous_state, current_state: current_state, timestamp: timestamp, error: error)
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
