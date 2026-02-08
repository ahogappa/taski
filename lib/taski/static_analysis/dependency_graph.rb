# frozen_string_literal: true

require "tsort"

module Taski
  module StaticAnalysis
    # Builds a complete dependency graph from a root task class
    # and provides topological sorting with cycle detection.
    class DependencyGraph
      include TSort

      def initialize
        @graph = {}
      end

      # Build dependency graph starting from root task class using static analysis
      # @param root_task_class [Class] The root task class to analyze
      # @return [DependencyGraph] self for method chaining
      def build_from(root_task_class)
        collect_dependencies(root_task_class)
        self
      end

      # Build dependency graph using cached_dependencies (runtime) instead of AST analysis
      # @param root_task_class [Class] The root task class
      # @return [DependencyGraph] self for method chaining
      def build_from_cached(root_task_class)
        collect_cached_dependencies(root_task_class)
        self
      end

      # Get topologically sorted task classes (dependencies first)
      # @return [Array<Class>] Sorted task classes
      # @raise [TSort::Cyclic] If circular dependency is detected
      def sorted
        tsort
      end

      # Check if the graph contains circular dependencies
      # @return [Boolean] true if circular dependencies exist
      def cyclic?
        tsort
        false
      rescue TSort::Cyclic
        true
      end

      # Get strongly connected components (useful for debugging cycles)
      # @return [Array<Array<Class>>] Groups of mutually dependent classes
      def strongly_connected_components
        each_strongly_connected_component.to_a
      end

      # Get task classes involved in cycles
      # @return [Array<Array<Class>>] Only components with size > 1 (cycles)
      def cyclic_components
        strongly_connected_components.select { |component| component.size > 1 }
      end

      # Get all task classes in the graph
      # @return [Array<Class>] All registered task classes
      def all_tasks
        @graph.keys
      end

      # Get direct dependencies for a task class
      # @param task_class [Class] The task class
      # @return [Set<Class>] Direct dependencies
      def dependencies_for(task_class)
        @graph.fetch(task_class, Set.new)
      end

      # TSort interface: iterate over all nodes
      def tsort_each_node(&block)
        @graph.each_key(&block)
      end

      # TSort interface: iterate over children (dependencies) of a node
      def tsort_each_child(node, &block)
        @graph.fetch(node, Set.new).each(&block)
      end

      private

      # Recursively collect all dependencies starting from a task class
      def collect_dependencies(task_class)
        return if @graph.key?(task_class)

        dependencies = Analyzer.analyze(task_class)
        @graph[task_class] = dependencies

        dependencies.each do |dep_class|
          collect_dependencies(dep_class)
        end
      end

      # Recursively collect dependencies using cached_dependencies
      def collect_cached_dependencies(task_class)
        return if @graph.key?(task_class)

        deps = task_class.cached_dependencies
        @graph[task_class] = deps.to_set

        deps.each { |dep| collect_cached_dependencies(dep) }
      end
    end
  end
end
