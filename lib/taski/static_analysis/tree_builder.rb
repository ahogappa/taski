# frozen_string_literal: true

require_relative "analyzer"

module Taski
  module StaticAnalysis
    # Builds a tree structure from a root task class for visualization.
    # This module extracts tree-building logic from Layout classes,
    # providing a shared implementation for progress displays.
    #
    # The tree nodes contain:
    # - task_class: The task class
    # - children: Array of child nodes
    # - is_section: Whether the task is a Section
    # - is_impl_candidate: Whether the task is a Section impl candidate
    # - is_circular: Whether this node creates a circular reference
    #
    # @example Building a tree
    #   tree = TreeBuilder.build_tree(RootTask)
    #   tree[:task_class]  # => RootTask
    #   tree[:children]    # => Array of child nodes
    #
    # @example Using with a dependency graph
    #   graph = DependencyGraph.new.build_from(RootTask)
    #   tree = TreeBuilder.build_tree(RootTask, dependency_graph: graph)
    module TreeBuilder
      class << self
        # Build a tree structure starting from the given root task class.
        #
        # @param root_task_class [Class] The root task class
        # @param dependency_graph [DependencyGraph, nil] Optional cached dependency graph
        # @return [Hash] Tree structure with task_class, children, is_section, etc.
        def build_tree(root_task_class, dependency_graph: nil)
          build_tree_node(root_task_class, Set.new, dependency_graph)
        end

        private

        def build_tree_node(task_class, ancestors, dependency_graph)
          is_circular = ancestors.include?(task_class)

          node = {
            task_class: task_class,
            is_section: section_class?(task_class),
            is_circular: is_circular,
            is_impl_candidate: false,
            children: []
          }

          return node if is_circular

          new_ancestors = ancestors + [task_class]
          dependencies = get_task_dependencies(task_class, dependency_graph)
          is_section = section_class?(task_class)

          dependencies.each do |dep|
            child_node = build_tree_node(dep, new_ancestors, dependency_graph)
            child_node[:is_impl_candidate] = is_section && nested_class?(dep, task_class)
            node[:children] << child_node
          end

          node
        end

        def get_task_dependencies(task_class, dependency_graph)
          # Use dependency graph if provided
          if dependency_graph
            return dependency_graph.dependencies_for(task_class).to_a
          end

          # Fallback to static analysis
          deps = Analyzer.analyze(task_class).to_a
          return deps unless deps.empty?

          # Fallback to cached_dependencies for test stubs
          if task_class.respond_to?(:cached_dependencies)
            task_class.cached_dependencies
          else
            []
          end
        end

        def section_class?(klass)
          !!(defined?(Taski::Section) && klass < Taski::Section)
        end

        def nested_class?(child_class, parent_class)
          parent_name = parent_class.name
          child_name = child_class.name
          return false if parent_name.nil? || parent_name.empty?
          return false if child_name.nil? || child_name.empty?

          child_name.start_with?("#{parent_name}::")
        end
      end
    end
  end
end
