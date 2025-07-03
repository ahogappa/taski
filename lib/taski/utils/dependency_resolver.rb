# frozen_string_literal: true

module Taski
  module Utils
    # Interface for dependency resolution functionality
    # Provides common logic for resolving dependencies and detecting circular dependencies
    module DependencyResolver
      private

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

          task_class.instance_variable_get(:@dependencies)&.each do |dep|
            dep_class = extract_class(dep)
            path_map[dep_class] = current_path + [task_class] unless path_map.key?(dep_class)
          end

          resolving.delete(task_class)
          resolved << task_class unless resolved.include?(task_class)
        end

        resolved
      end

      # Resolve method for dependency graph (called by resolve_dependencies)
      # @param queue [Array] Queue of tasks to process
      # @param resolved [Array] Array of resolved tasks
      # @param options [Hash] Optional parameters for customization
      # @return [self] Returns self for method chaining
      def resolve_common(queue, resolved, options = {})
        @dependencies ||= []

        @dependencies.each do |task|
          task_class = extract_class(task)

          # Reorder in resolved list for correct priority
          resolved.delete(task_class) if resolved.include?(task_class)
          queue << task_class
        end

        # Call custom hook if provided
        options[:custom_hook]&.call

        self
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
        Utils::CircularDependencyHelpers.build_error_message(cycle_path, "dependency")
      end
    end
  end
end
