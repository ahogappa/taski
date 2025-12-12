# frozen_string_literal: true

require_relative "static_analysis/analyzer"
require_relative "execution/registry"
require_relative "execution/coordinator"
require_relative "execution/task_wrapper"

module Taski
  # Base class for tasks with automatic dependency resolution
  class Task
    class << self
      # Define exported values that this task produces
      #
      # @param export_methods [Array<Symbol>] Names of methods to export
      def exports(*export_methods)
        @exported_methods = export_methods

        export_methods.each do |method|
          define_instance_reader(method)
          define_class_accessor(method)
        end
      end

      # Get the list of exported methods
      #
      # @return [Array<Symbol>] List of exported method names
      def exported_methods
        @exported_methods ||= []
      end

      # Get cached dependencies for this task
      #
      # @return [Set<Class>] Set of dependency classes
      def cached_dependencies
        @dependencies_cache ||= StaticAnalysis::Analyzer.analyze(self)
      end

      # Clear the dependency cache
      def clear_dependency_cache
        @dependencies_cache = nil
      end

      # Run the task and return the result
      #
      # @return [Object] The result of the task execution
      def run
        cached_wrapper.run
      end

      # Clean the task (executes in reverse dependency order)
      #
      # @return [Object] The result of the task cleanup
      def clean
        cached_wrapper.clean
      end

      # Get the global registry for this task system
      # This registry is shared across all task classes
      #
      # @return [Execution::Registry] The registry instance
      def registry
        Taski.global_registry
      end

      # Get the global coordinator for this task system
      #
      # @return [Execution::Coordinator] The coordinator instance
      def coordinator
        @coordinator ||= Execution::Coordinator.new(
          registry: registry,
          analyzer: StaticAnalysis::Analyzer
        )
      end

      # Reset the task system (clear all caches and registrations)
      def reset!
        registry.reset!
        Taski.reset_global_registry!
        @coordinator = nil
      end

      # Display dependency tree for this task
      #
      # @return [String] Tree representation of dependencies
      def tree
        build_tree(self, "", Set.new)
      end

      private

      # Build tree representation recursively
      #
      # @param task_class [Class] Current task class
      # @param prefix [String] Current line prefix
      # @param visited [Set] Set of visited task classes
      # @return [String] Tree string
      def build_tree(task_class, prefix, visited)
        result = "#{task_class.name}\n"
        return result if visited.include?(task_class)

        visited.add(task_class)
        dependencies = task_class.cached_dependencies.to_a

        dependencies.each_with_index do |dep, index|
          is_last = (index == dependencies.size - 1)
          result += format_dependency_branch(dep, prefix, is_last, visited)
        end

        result
      end

      # Format a dependency branch in the tree
      #
      # @param dep [Class] Dependency class
      # @param prefix [String] Current line prefix
      # @param is_last [Boolean] Whether this is the last dependency
      # @param visited [Set] Set of visited task classes
      # @return [String] Formatted branch string
      def format_dependency_branch(dep, prefix, is_last, visited)
        connector, extension = tree_connector_chars(is_last)
        dep_tree = build_tree(dep, "#{prefix}#{extension}", visited)

        result = "#{prefix}#{connector}"
        lines = dep_tree.lines
        result += lines.first
        lines[1..].each { |line| result += line }
        result
      end

      # Get tree connector characters
      #
      # @param is_last [Boolean] Whether this is the last item
      # @return [Array<String, String>] Connector and extension characters
      def tree_connector_chars(is_last)
        if is_last
          ["└── ", "    "]
        else
          ["├── ", "│   "]
        end
      end

      # Get or create a cached wrapper for this task
      #
      # @return [Execution::TaskWrapper] The task wrapper
      def cached_wrapper
        registry.get_or_create(self) do
          task_instance = allocate
          task_instance.send(:initialize)
          Execution::TaskWrapper.new(
            task_instance,
            registry: registry,
            coordinator: coordinator
          )
        end
      end

      # Define an instance reader for an exported value
      #
      # @param method [Symbol] The method name
      def define_instance_reader(method)
        # Remove existing method to avoid redefinition warning
        undef_method(method) if method_defined?(method)

        # Define reader method
        define_method(method) do
          # Read from instance variable
          # NOTE: Using instance_variable_get is unavoidable here for reading
          # dynamically defined exported values. This is part of the exports mechanism.
          instance_variable_get("@#{method}")
        end
      end

      # Define a class-level accessor for an exported value
      #
      # @param method [Symbol] The method name
      def define_class_accessor(method)
        # Remove existing method to avoid redefinition warning
        singleton_class.undef_method(method) if singleton_class.method_defined?(method)

        define_singleton_method(method) do
          cached_wrapper.get_exported_value(method)
        end
      end
    end

    # Run the task (must be implemented by subclasses)
    #
    # @raise [NotImplementedError] If not implemented by subclass
    def run
      raise NotImplementedError, "Subclasses must implement the run method"
    end

    # Clean the task (optional, can be overridden by subclasses)
    # Default implementation does nothing
    def clean
      # Default: no-op
    end

    # Reset all exported values to nil
    def reset!
      self.class.exported_methods.each do |method|
        # NOTE: Using instance_variable_set is unavoidable here for resetting
        # dynamically defined exported values. This is part of the exports mechanism.
        instance_variable_set("@#{method}", nil)
      end
    end
  end
end
