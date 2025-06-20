# frozen_string_literal: true

require "set"
require_relative "../dependency_analyzer"

module Taski
  class Task
    class << self
      # === Dependency Resolution ===

      # Resolve method for dependency graph (called by resolve_dependencies)
      # @param queue [Array] Queue of tasks to process
      # @param resolved [Array] Array of resolved tasks
      # @return [self] Returns self for method chaining
      def resolve(queue, resolved)
        @dependencies ||= []

        @dependencies.each do |task|
          task_class = extract_class(task)

          # Reorder in resolved list for correct priority
          resolved.delete(task_class) if resolved.include?(task_class)
          queue << task_class
        end

        # Create getter methods for defined values
        create_defined_methods

        self
      end

      # Resolve all dependencies in topological order with circular dependency detection
      # @return [Array<Class>] Array of tasks in dependency order
      def resolve_dependencies
        queue = [self]
        resolved = []
        visited = Set.new
        resolving = Set.new  # Track currently resolving tasks
        path_map = {self => []}  # Track paths to each task

        while queue.any?
          task_class = queue.shift
          next if visited.include?(task_class)

          # Check for circular dependency
          if resolving.include?(task_class)
            # Build error message with path information
            cycle_path = build_cycle_path(task_class, path_map)
            raise CircularDependencyError, build_circular_dependency_message(cycle_path)
          end

          resolving << task_class
          visited << task_class

          # Store current path for dependencies
          current_path = path_map[task_class] || []

          # Let task resolve its dependencies
          task_class.resolve(queue, resolved)

          # Track paths for each dependency
          task_class.instance_variable_get(:@dependencies)&.each do |dep|
            dep_class = extract_class(dep)
            path_map[dep_class] = current_path + [task_class] unless path_map.key?(dep_class)
          end

          resolving.delete(task_class)
          resolved << task_class unless resolved.include?(task_class)
        end

        resolved
      end

      private

      # Build the cycle path from path tracking information
      def build_cycle_path(task_class, path_map)
        path = path_map[task_class] || []
        path + [task_class]
      end

      # Build detailed error message for circular dependencies
      def build_circular_dependency_message(cycle_path)
        path_names = cycle_path.map { |klass| klass.name || klass.to_s }

        message = "Circular dependency detected!\n"
        message += "Cycle: #{path_names.join(" → ")}\n\n"
        message += "Detailed dependency chain:\n"

        cycle_path.each_cons(2).with_index do |(from, to), index|
          message += "  #{index + 1}. #{from.name} depends on → #{to.name}\n"
        end

        message
      end

      public

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
        clean_deps = DependencyAnalyzer.analyze_method(self, :clean)
        (build_deps + clean_deps).uniq
      end

      # Add dependencies that don't already exist
      # @param dep_classes [Array<Class>] Array of dependency classes
      def add_unique_dependencies(dep_classes)
        dep_classes.each do |dep_class|
          next if dep_class == self || dependency_exists?(dep_class)
          add_dependency(dep_class)
        end
      end

      # Add a single dependency
      # @param dep_class [Class] Dependency class to add
      def add_dependency(dep_class)
        @dependencies ||= []
        @dependencies << {klass: dep_class}
      end

      # Check if dependency already exists
      # @param dep_class [Class] Dependency class to check
      # @return [Boolean] True if dependency exists
      def dependency_exists?(dep_class)
        (@dependencies || []).any? { |d| d[:klass] == dep_class }
      end
    end
  end
end
