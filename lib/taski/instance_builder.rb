# frozen_string_literal: true

require_relative "task/core_constants"

module Taski
  # Instance building logic that integrates all components
  class InstanceBuilder
    include TaskComponent

    def initialize(task_class)
      super
    end

    def build_instance
      check_circular_dependency
      with_build_tracking do
        create_and_execute_instance
      end
    end

    # Execute block with comprehensive build logging and progress display (class method)
    # @param task_name [String] Name of the task being built
    # @param dependencies [Array] List of dependencies
    # @param args [Hash] Build arguments for parametrized builds
    # @param parent_task [Class] Parent task class for rescue_deps handling
    # @yield Block to execute with logging
    # @return [Object] Result of the block execution
    def self.with_build_logging(task_name, dependencies: [], args: nil, parent_task: nil)
      start_time = Time.now
      signal_handler = nil

      begin
        # Setup signal handling
        signal_handler = SignalHandler.new
        signal_handler.setup_signal_traps

        # Start logging and progress
        Taski.logger.task_build_start(task_name, dependencies: dependencies, args: args)
        Taski.progress_display&.start_task(task_name, dependencies: dependencies)

        result = yield

        # Check for signals after execution
        if signal_handler&.signal_received?
          signal_name = signal_handler.signal_name
          exception = signal_handler.convert_signal_to_exception(signal_name)
          raise exception
        end

        duration = Time.now - start_time

        # Complete progress and log success
        Taski.progress_display&.complete_task(task_name, duration: duration)
        Taski.logger.task_build_complete(task_name, duration: duration)

        result
      rescue => exception
        duration = Time.now - start_time

        # Handle interrupted tasks specially
        if exception.is_a?(TaskInterruptedException)
          Taski.progress_display&.interrupt_task(task_name, error: exception, duration: duration)
        else
          Taski.progress_display&.fail_task(task_name, error: exception, duration: duration)
        end
        Taski.logger.task_build_failed(task_name, error: exception, duration: duration)

        # Check for rescue_deps handler first
        if handle_rescue_deps(parent_task, exception, task_name)
          return nil
        end

        # Wrap exception in TaskBuildError unless it already is one
        if exception.is_a?(TaskBuildError)
          raise
        else
          # Build error message
          error_message = "Failed to build task #{task_name}"
          error_message += " with args #{format_args(args)}" if args && !args.empty?
          error_message += ": #{exception.message}"

          raise TaskBuildError, error_message
        end
      end
    end

    # Handle rescue_deps error handling
    # @param parent_task [Class] Parent task class
    # @param exception [Exception] Exception to handle
    # @param task_name [String] Failed task name
    # @return [Boolean] true if handled and should continue, false if should fall through
    def self.handle_rescue_deps(parent_task, exception, task_name)
      return false unless parent_task

      handler_pair = parent_task.find_dependency_rescue_handler(exception)
      return false unless handler_pair

      _exception_class, handler = handler_pair
      failed_task_class = resolve_task_class(task_name)

      begin
        result = handler.call(exception, failed_task_class)
      rescue => handler_error
        warn "rescue_deps handler failed: #{handler_error.message}"
        return false
      end

      handle_rescue_result(result)
    end

    # Resolve task class from name
    # @param task_name [String] Task name
    # @return [Class, nil] Task class or nil if not found
    def self.resolve_task_class(task_name)
      Object.const_get(task_name)
    rescue NameError
      nil
    end

    # Handle the result from rescue handler
    # @param result [Object] Result from rescue handler
    # @return [Boolean] true if should continue, false if should fall through
    def self.handle_rescue_result(result)
      case result
      when nil
        true  # Continue processing
      when :reraise
        false  # Fall through to normal error handling
      when Exception
        raise result
      else
        false  # For any other return value, fall through to normal error handling
      end
    end

    # Format arguments hash for display in error messages
    # @param args [Hash] Arguments hash
    # @return [String] Formatted arguments string
    def self.format_args(args)
      return "" if args.nil? || args.empty?

      formatted_pairs = args.map do |key, value|
        "#{key}: #{value.inspect}"
      end
      "{#{formatted_pairs.join(", ")}}"
    end

    private

    # Check for circular dependencies and raise error if detected
    # @raise [CircularDependencyError] If circular dependency is detected
    def check_circular_dependency
      thread_key = build_thread_key
      if Thread.current[thread_key]
        handle_circular_dependency_detected
      end
    end

    # Handle the case when circular dependency is detected
    # @raise [CircularDependencyError] Always raises with detailed message
    def handle_circular_dependency_detected
      # Build dependency path for better error message
      cycle_path = build_current_dependency_path
      raise CircularDependencyError, build_runtime_circular_dependency_message(cycle_path)
    end

    # Build current dependency path from thread-local storage
    # @return [Array<Class>] Array of classes in the current build path
    def build_current_dependency_path
      path = []
      Thread.current.keys.each do |key|
        if key.to_s.end_with?(Taski::Task::CoreConstants::THREAD_KEY_SUFFIX) && Thread.current[key]
          class_name = key.to_s.sub(Taski::Task::CoreConstants::THREAD_KEY_SUFFIX, "")
          begin
            path << Object.const_get(class_name)
          rescue NameError
            # Skip if class not found
          end
        end
      end
      path << @task_class
    end

    # Build runtime circular dependency error message
    # @param cycle_path [Array<Class>] The circular dependency path
    # @return [String] Formatted error message
    def build_runtime_circular_dependency_message(cycle_path)
      build_circular_dependency_error_message(cycle_path, "runtime")
    end

    # Build detailed error message for circular dependencies
    # @param cycle_path [Array<Class>] The circular dependency path
    # @param context [String] Context of the error (dependency, runtime)
    # @return [String] Formatted error message
    def build_circular_dependency_error_message(cycle_path, context = "dependency")
      path_names = cycle_path.map { |klass| klass.name || klass.to_s }

      message = "Circular dependency detected!\n"
      message += "Cycle: #{path_names.join(" → ")}\n\n"
      message += "The #{context} chain is:\n"

      cycle_path.each_cons(2).with_index do |(from, to), index|
        action = (context == "dependency") ? "depends on" : "is trying to build"
        message += "  #{index + 1}. #{from.name} #{action} → #{to.name}\n"
      end

      message += "\nThis creates an infinite loop that cannot be resolved." if context == "dependency"
      message
    end

    # Create instance, build dependencies, and execute with logging
    # @return [Task] The executed task instance
    def create_and_execute_instance
      instance = create_instance_with_dependencies
      execute_instance_with_logging(instance)
    end

    # Create new instance and build its dependencies
    # @return [Task] Task instance with dependencies built
    def create_instance_with_dependencies
      instance = @task_class.new
      @task_class.build_dependencies
      instance
    end

    # Execute instance with proper logging and parent context
    # @param instance [Task] Task instance to execute
    # @return [Task] The executed task instance
    def execute_instance_with_logging(instance)
      parent_task = current_parent_task
      with_build_logging(@task_class.name.to_s,
        dependencies: @task_class.dependencies,
        parent_task: parent_task) do
        instance.run
        instance
      end
    end

    # Execute block with comprehensive build logging and progress display
    # @param task_name [String] Name of the task being built
    # @param dependencies [Array] List of dependencies
    # @param args [Hash] Build arguments for parametrized builds
    # @param parent_task [Class] Parent task class for rescue_deps handling
    # @yield Block to execute with logging
    # @return [Object] Result of the block execution
    def with_build_logging(task_name, dependencies: [], args: nil, parent_task: nil)
      self.class.with_build_logging(task_name, dependencies: dependencies, args: args, parent_task: parent_task) { yield }
    end

    # Get current parent task from thread-local storage
    # @return [Task, nil] Current parent task or nil
    def current_parent_task
      Thread.current[Taski::Task::TASKI_CURRENT_PARENT_TASK_KEY]
    end

    attr_reader :circular_dependency_detector
  end
end
