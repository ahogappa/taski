# frozen_string_literal: true

require_relative "static_analysis/analyzer"
require_relative "execution/registry"
require_relative "execution/task_wrapper"

module Taski
  # Base class for all tasks in the Taski framework.
  # Tasks define units of work with dependencies and exported values.
  #
  # @example Defining a simple task
  #   class MyTask < Taski::Task
  #     exports :result
  #
  #     def run
  #       @result = "completed"
  #     end
  #   end
  class Task
    class << self
      ##
      # Callback invoked when a subclass is created.
      # Automatically creates a task-specific Error class for each subclass.
      # @param subclass [Class] The newly created subclass.
      def inherited(subclass)
        super
        # Create TaskClass::Error that inherits from Taski::TaskError
        error_class = Class.new(Taski::TaskError)
        subclass.const_set(:Error, error_class)
      end

      ##
      # Declares exported methods that will be accessible after task execution.
      # Creates instance reader and class accessor methods for each export.
      # @param export_methods [Array<Symbol>] The method names to export.
      def exports(*export_methods)
        @exported_methods = export_methods

        export_methods.each do |method|
          define_instance_reader(method)
          define_class_accessor(method)
        end
      end

      ##
      # Returns the list of exported method names.
      # @return [Array<Symbol>] The exported method names.
      def exported_methods
        @exported_methods ||= []
      end

      ##
      # Creates a fresh TaskWrapper instance for re-execution support.
      # Use class methods (e.g., MyTask.result) for cached single execution.
      # @return [Execution::TaskWrapper] A new wrapper for this task.
      def new
        fresh_wrapper
      end

      ##
      # Returns cached static dependencies for this task class.
      # Dependencies are analyzed from the run method body using static analysis.
      # @return [Set<Class>] The set of task classes this task depends on.
      def cached_dependencies
        @dependencies_cache ||= StaticAnalysis::Analyzer.analyze(self)
      end

      ##
      # Clears the cached dependency analysis.
      # Useful when task code has changed and dependencies need to be re-analyzed.
      def clear_dependency_cache
        @dependencies_cache = nil
      end

      ##
      # Executes the task and all its dependencies.
      # Creates a fresh registry each time for independent execution.
      # @param args [Hash] User-defined arguments accessible via Taski.args.
      # @param workers [Integer, nil] Number of worker threads for parallel execution.
      #   Must be a positive integer or nil.
      #   Use workers: 1 for sequential execution (useful for debugging).
      # @raise [ArgumentError] If workers is not a positive integer or nil.
      # @return [Object] The result of task execution.
      def run(args: {}, workers: nil)
        with_execution_setup(args: args, workers: workers) { |wrapper| wrapper.run }
      end

      ##
      # Executes the clean phase for the task and all its dependencies.
      # Clean is executed in reverse dependency order.
      # Creates a fresh registry each time for independent execution.
      # @param args [Hash] User-defined arguments accessible via Taski.args.
      # @param workers [Integer, nil] Number of worker threads for parallel execution.
      #   Must be a positive integer or nil.
      # @raise [ArgumentError] If workers is not a positive integer or nil.
      def clean(args: {}, workers: nil)
        with_execution_setup(args: args, workers: workers) { |wrapper| wrapper.clean }
      end

      ##
      # Execute run followed by clean in a single operation.
      # If run fails, clean is still executed for resource release.
      # Creates a fresh registry for both operations to share.
      #
      # @param args [Hash] User-defined arguments accessible via Taski.args.
      # @param workers [Integer, nil] Number of worker threads for parallel execution.
      #   Must be a positive integer or nil.
      # @raise [ArgumentError] If workers is not a positive integer or nil.
      # @return [Object] The result of task execution
      def run_and_clean(args: {}, workers: nil)
        with_execution_setup(args: args, workers: workers) { |wrapper| wrapper.run_and_clean }
      end

      ##
      # Resets the task state and progress display.
      # Useful for testing or re-running tasks from scratch.
      def reset!
        Taski.reset_args!
        Taski.reset_progress_display!
        @circular_dependency_checked = false
      end

      ##
      # Renders a static tree representation of the task dependencies.
      # @return [String] The rendered tree string.
      def tree
        Execution::TreeProgressDisplay.render_static_tree(self)
      end

      private

      ##
      # Sets up execution environment and yields a fresh wrapper.
      # Handles workers validation, args lifecycle, and dependency validation.
      # @param args [Hash] User-defined arguments
      # @param workers [Integer, nil] Number of worker threads
      # @yield [wrapper] Block receiving the fresh wrapper to execute
      # @return [Object] The result of the block
      def with_execution_setup(args:, workers:)
        validate_workers!(workers)
        Taski.with_args(options: args.merge(_workers: workers), root_task: self) do
          validate_no_circular_dependencies!
          yield fresh_wrapper
        end
      end

      ##
      # Creates a fresh TaskWrapper with its own registry.
      # Used for class method execution (Task.run) where each call is independent.
      # @return [Execution::TaskWrapper] A new wrapper with fresh registry.
      def fresh_wrapper
        fresh_registry = Execution::Registry.new
        task_instance = allocate
        task_instance.__send__(:initialize)
        wrapper = Execution::TaskWrapper.new(
          task_instance,
          registry: fresh_registry,
          execution_context: Execution::ExecutionContext.current
        )
        fresh_registry.register(self, wrapper)
        wrapper
      end

      ##
      # Defines an instance reader method for an exported value.
      # @param method [Symbol] The method name to define.
      def define_instance_reader(method)
        undef_method(method) if method_defined?(method)

        define_method(method) do
          # @type self: Task
          instance_variable_get("@#{method}")
        end
      end

      ##
      # Defines a class accessor method for an exported value.
      # When called inside an execution, returns cached value from registry.
      # When called outside execution, creates fresh execution.
      # @param method [Symbol] The method name to define.
      def define_class_accessor(method)
        singleton_class.undef_method(method) if singleton_class.method_defined?(method)

        define_singleton_method(method) do
          # Check if running inside an execution with a registry
          registry = Taski.current_registry
          if registry
            # Inside execution - get or create wrapper in current registry
            # This handles both pre-registered dependencies and dynamic ones (like Section impl)
            wrapper = registry.get_or_create(self) do
              task_instance = allocate
              task_instance.__send__(:initialize)
              Execution::TaskWrapper.new(
                task_instance,
                registry: registry,
                execution_context: Execution::ExecutionContext.current
              )
            end
            wrapper.get_exported_value(method)
          else
            # Outside execution - fresh execution (top-level call)
            Taski.with_args(options: {}, root_task: self) do
              validate_no_circular_dependencies!
              fresh_wrapper.get_exported_value(method)
            end
          end
        end
      end

      ##
      # Validates that no circular dependencies exist in the task graph.
      # @raise [Taski::CircularDependencyError] If circular dependencies are detected.
      def validate_no_circular_dependencies!
        return if @circular_dependency_checked

        graph = StaticAnalysis::DependencyGraph.new.build_from(self)
        cyclic_components = graph.cyclic_components

        if cyclic_components.any?
          raise Taski::CircularDependencyError.new(cyclic_components)
        end

        @circular_dependency_checked = true
      end

      ##
      # Validates the workers parameter.
      # @param workers [Object] The workers parameter to validate.
      # @raise [ArgumentError] If workers is not a positive integer or nil.
      def validate_workers!(workers)
        return if workers.nil?

        unless workers.is_a?(Integer) && workers >= 1
          raise ArgumentError, "workers must be a positive integer or nil, got: #{workers.inspect}"
        end
      end
    end

    ##
    # Executes the task's main logic.
    # Subclasses must override this method to implement task behavior.
    # @raise [NotImplementedError] If not overridden in a subclass.
    def run
      raise NotImplementedError, "Subclasses must implement the run method"
    end

    ##
    # Cleans up resources after task execution.
    # Override in subclasses to implement cleanup logic.
    def clean
    end

    # Override system() to capture subprocess output through the pipe-based architecture.
    # Uses Kernel.system with :out option to redirect output to the task's pipe.
    # If user provides :out or :err options, they are respected (no automatic redirection).
    # @param args [Array] Command arguments (shell mode if single string, exec mode if array)
    # @param opts [Hash] Options passed to Kernel.system
    # @return [Boolean, nil] true if command succeeded, false if failed, nil if command not found
    def system(*args, **opts)
      write_io = $stdout.respond_to?(:current_write_io) ? $stdout.current_write_io : nil

      if write_io && !opts.key?(:out)
        # Redirect subprocess output to the task's pipe (stderr merged into stdout)
        Kernel.system(*args, out: write_io, err: [:child, :out], **opts)
      else
        # No capture active or user provided custom :out, use normal system
        Kernel.system(*args, **opts)
      end
    end

    # Groups related output within a task for organized progress display.
    # The group name is shown in the progress tree as a child of the task.
    # Groups cannot be nested.
    #
    # @param name [String] The group name to display
    # @yield The block to execute within the group
    # @return [Object] The result of the block
    # @raise Re-raises any exception from the block after marking group as failed
    #
    # @example
    #   def run
    #     group("Preparing") do
    #       puts "Checking dependencies..."
    #       puts "Validating config..."
    #     end
    #     group("Deploying") do
    #       puts "Uploading files..."
    #     end
    #   end
    def group(name)
      context = Execution::ExecutionContext.current
      context&.notify_group_started(self.class, name)
      start_time = Time.now

      begin
        result = yield
        duration_ms = ((Time.now - start_time) * 1000).round(0)
        context&.notify_group_completed(self.class, name, duration: duration_ms)
        result
      rescue => e
        duration_ms = ((Time.now - start_time) * 1000).round(0)
        context&.notify_group_completed(self.class, name, duration: duration_ms, error: e)
        raise
      end
    end

    ##
    # Resets the instance's exported values to nil.
    def reset!
      self.class.exported_methods.each do |method|
        instance_variable_set("@#{method}", nil)
      end
    end
  end
end
