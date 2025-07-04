# frozen_string_literal: true

require_relative "../dependency_analyzer"
require_relative "../utils/dependency_resolver"

module Taski
  class Task
    class << self
      # === Dependency Resolution ===

      # Resolve method for dependency graph (called by resolve_dependencies)
      # @param queue [Array] Queue of tasks to process
      # @param resolved [Array] Array of resolved tasks
      # @return [self] Returns self for method chaining
      def resolve(queue, resolved)
        resolve_common(queue, resolved, custom_hook: -> { create_defined_methods })
      end

      # Resolve all dependencies in topological order with circular dependency detection
      # @return [Array<Class>] Array of tasks in dependency order
      def resolve_dependencies
        resolve_dependencies_common
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
        run_deps = DependencyAnalyzer.analyze_method(self, :run)
        clean_deps = DependencyAnalyzer.analyze_method(self, :clean)
        (build_deps + run_deps + clean_deps).uniq
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

      private

      include Utils::DependencyUtils
      include Utils::DependencyResolver
      private :extract_class
    end
  end
end
