# frozen_string_literal: true

require_relative "reference"
require_relative "exceptions"
require_relative "dependency_analyzer"

module Taski
  module TaskInterface
    module ClassMethods
      # Get the dependencies of this task or section
      # @return [Array<Hash>] Array of dependency hashes in format [{klass: TaskClass}, ...]
      def dependencies
        @dependencies ||= []
      end

      def dependencies=(deps)
        @dependencies = deps
      end

      # Resolve all dependencies in topological order with circular dependency detection
      # @return [Array<Class>] Array of tasks in dependency order
      def resolve_dependencies
        resolve_dependencies_common
      end

      def run(**args)
        raise NotImplementedError, "#{self.class} must implement run"
      end

      alias_method :build, :run

      def clean(**args)
        # Default implementation does nothing - allows optional cleanup in subclasses
        # Subclasses can override this method to implement cleanup logic
      end

      alias_method :drop, :clean

      # Reset the task or section state
      # @return [Object] Implementation-specific return value
      def reset!
        raise NotImplementedError, "#{self.class} must implement reset!"
      end

      # Resolve method for dependency graph (called by resolve_dependencies)
      # @param queue [Array] Queue of tasks to process
      # @param resolved [Array] Array of resolved tasks
      # @yield Optional block to execute during resolution
      # @return [self] Returns self for method chaining
      def resolve(queue, resolved, &block)
        resolve_common(queue, resolved, &block)
      end

      def tree
        raise NotImplementedError, "#{self.class} must implement tree"
      end

      private

      # Extract class from dependency hash (module-level method)
      # @param dep [Hash, Class] Dependency information
      # @return [Class] The dependency class
      def extract_class(dep)
        case dep
        when Class
          dep
        when Hash
          klass = dep[:klass]
          klass.is_a?(Reference) ? klass.deref : klass
        else
          dep
        end
      end

      # Resolve method for dependency graph (called by resolve_dependencies)
      # @param queue [Array] Queue of tasks to process
      # @param resolved [Array] Array of resolved tasks
      # @param options [Hash] Optional parameters for customization
      # @yield Optional block to execute during resolution
      # @return [self] Returns self for method chaining
      def resolve_common(queue, resolved, options = {}, &block)
        @dependencies ||= []

        @dependencies.each do |task|
          task_class = extract_class(task)

          # Reorder in resolved list for correct priority
          resolved.delete(task_class) if resolved.include?(task_class)
          queue << task_class
        end

        # Call custom hook if provided (legacy support)
        options[:custom_hook]&.call

        # Execute the provided block if given (new preferred way)
        yield if block_given?

        self
      end

      # Resolve all dependencies in topological order with circular dependency detection
      # @return [Array<Class>] Array of tasks in dependency order
      def resolve_dependencies_common
        # Phase 2: Resolve pending references before dependency resolution
        # This is safe to call always - tasks without pending references simply do nothing
        resolve_pending_references

        queue = [self]
        resolved = []
        visited = Set.new
        resolving = Set.new
        path_map = {self => []}

        while queue.any?
          task_class = queue.shift
          next if visited.include?(task_class)

          if resolving.include?(task_class)
            cycle_path = build_cycle_path(task_class, path_map)
            raise CircularDependencyError, build_circular_dependency_message(cycle_path)
          end

          resolving << task_class
          visited << task_class

          current_path = path_map[task_class] || []
          task_class.resolve(queue, resolved)

          task_class.dependencies.each do |dep|
            dep_class = extract_class(dep)
            path_map[dep_class] = current_path + [task_class] unless path_map.key?(dep_class)
          end

          resolving.delete(task_class)
          resolved << task_class unless resolved.include?(task_class)
        end

        resolved
      end

      # Default implementation for resolving pending references
      # This is a no-op by default, but can be overridden by classes
      # that use forward references (like Task with DefineAPI)
      # @return [void]
      def resolve_pending_references
        # No-op default implementation
        # Task classes using ref() should override this
      end

      # Add a single dependency
      # @param dep_class [Class] Dependency class to add
      def add_dependency(dep_class)
        dependencies << {klass: dep_class}
      end

      # Check if dependency already exists
      # @param dep_class [Class] Dependency class to check
      # @return [Boolean] True if dependency exists
      def dependency_exists?(dep_class)
        dependencies.any? { |d| d[:klass] == dep_class }
      end

      # Add dependencies that don't already exist
      # @param dep_classes [Array<Class>] Array of dependency classes
      def add_unique_dependencies(dep_classes)
        dep_classes.each do |dep_class|
          next if dep_class == self || dependency_exists?(dep_class)
          add_dependency(dep_class)
        end
      end

      # Build the cycle path from path tracking information
      # @param task_class [Class] Current task class
      # @param path_map [Hash] Map of paths to each task
      # @return [Array] Cycle path array
      def build_cycle_path(task_class, path_map)
        path = path_map[task_class] || []
        path + [task_class]
      end

      # Build detailed error message for circular dependencies
      # @param cycle_path [Array] Array representing the circular dependency path
      # @return [String] Formatted error message
      def build_circular_dependency_message(cycle_path)
        build_circular_dependency_error_message(cycle_path, "dependency")
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

      def ensure_instance_built
        raise NotImplementedError, "#{self.class} must implement ensure_instance_built"
      end

      # === Static Analysis ===

      # Analyze dependencies when methods are defined
      def analyze_dependencies_at_definition
        dependencies = gather_static_dependencies
        add_unique_dependencies(dependencies)
      end

      # Gather dependencies from build and clean methods
      # @return [Array<Class>] Array of dependency classes
      def gather_static_dependencies
        build_deps = DependencyAnalyzer.analyze_method(self, :build)
        run_deps = DependencyAnalyzer.analyze_method(self, :run)
        clean_deps = DependencyAnalyzer.analyze_method(self, :clean)
        (build_deps + run_deps + clean_deps).uniq
      end
    end
  end
end
