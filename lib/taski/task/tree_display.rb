# frozen_string_literal: true

require_relative "../utils/tree_display"

module Taski
  class Task
    # Module for displaying task dependency trees
    module TreeDisplay
      include Utils::TreeDisplay

      # Display dependency tree for this task
      # @param prefix [String] Current indentation prefix
      # @param visited [Set] Set of visited classes to prevent infinite loops
      # @return [String] Formatted dependency tree
      def tree(prefix = "", visited = Set.new, color: TreeColors.enabled?)
        should_return_early, early_result, new_visited = handle_circular_dependency_check(visited, self, prefix)
        return early_result if should_return_early

        task_name = color ? TreeColors.task(name) : name
        result = "#{prefix}#{task_name}\n"

        dependencies = @dependencies || []
        result += render_dependencies_tree(dependencies, prefix, new_visited, color)

        result
      end
    end
  end
end
