# frozen_string_literal: true

module Taski
  module Utils
    # Helper module for tree display functionality
    # Provides common logic for displaying dependency trees
    module TreeDisplayHelper
      private

      # Render dependencies as tree structure
      # @param dependencies [Array] Array of dependency objects
      # @param prefix [String] Current indentation prefix
      # @param visited [Set] Set of visited classes
      # @param color [Boolean] Whether to use color output
      # @return [String] Formatted dependency tree string
      def render_dependencies_tree(dependencies, prefix, visited, color)
        result = ""

        dependencies = dependencies.uniq { |dep| extract_class(dep) }
        dependencies.each_with_index do |dep, index|
          dep_class = extract_class(dep)
          is_last = index == dependencies.length - 1

          connector_text = is_last ? "└── " : "├── "
          connector = color ? TreeColors.connector(connector_text) : connector_text
          child_prefix_text = is_last ? "    " : "│   "
          child_prefix = prefix + (color ? TreeColors.connector(child_prefix_text) : child_prefix_text)

          # For the dependency itself, we want to use the connector
          # For its children, we want to use the child_prefix
          dep_tree = if dep_class.respond_to?(:tree)
            dep_class.tree(child_prefix, visited, color: color)
          else
            "#{child_prefix}#{dep_class.name}\n"
          end

          # Replace the first line (which has child_prefix) with the proper connector
          dep_lines = dep_tree.lines
          if dep_lines.any?
            # Replace the first line prefix with connector
            first_line = dep_lines[0]
            fixed_first_line = first_line.sub(/^#{Regexp.escape(child_prefix)}/, prefix + connector)
            result += fixed_first_line
            # Add the rest of the lines as-is
            result += dep_lines[1..].join if dep_lines.length > 1
          else
            dep_name = color ? TreeColors.task(dep_class.name) : dep_class.name
            result += "#{prefix}#{connector}#{dep_name}\n"
          end
        end

        result
      end

      # Check for circular dependencies and handle visited set
      # @param visited [Set] Set of visited classes
      # @param current_class [Class] Current class being processed
      # @param prefix [String] Current indentation prefix
      # @return [Array] Returns [should_return_early, result_string, new_visited_set]
      def handle_circular_dependency_check(visited, current_class, prefix)
        if visited.include?(current_class)
          return [true, "#{prefix}#{current_class.name} (circular)\n", visited]
        end

        new_visited = visited.dup
        new_visited << current_class
        [false, nil, new_visited]
      end
    end
  end
end
