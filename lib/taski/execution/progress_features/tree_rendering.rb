# frozen_string_literal: true

module Taski
  module Execution
    module ProgressFeatures
      # Provides tree rendering utilities for displaying task hierarchies.
      # Include this module to get tree traversal and prefix generation methods.
      #
      # @example
      #   class MyTreeDisplay
      #     include ProgressFeatures::TreeRendering
      #
      #     def render(tree)
      #       each_tree_node(tree) do |node, depth, is_last|
      #         prefix = tree_prefix(depth, is_last)
      #         puts "#{prefix}#{node[:task_class].name}"
      #       end
      #     end
      #   end
      module TreeRendering
        TREE_COLOR = "\e[90m"
        RESET_COLOR = "\e[0m"

        TREE_CONNECTOR_LAST = "\u2514\u2500\u2500 "     # "└── "
        TREE_CONNECTOR_BRANCH = "\u251c\u2500\u2500 "   # "├── "
        TREE_INDENT_EMPTY = "    "                      # 4 spaces
        TREE_INDENT_BAR = "\u2502   "                   # "│   "

        # Traverse a tree structure and yield each node with its depth and position.
        # @param tree [Hash] Tree node with :task_class and :children keys
        # @param depth [Integer] Current depth (0 = root)
        # @param is_last [Boolean] Whether this node is the last sibling
        # @yield [node, depth, is_last] Called for each node
        def each_tree_node(tree, depth: 0, is_last: true, &block)
          yield tree, depth, is_last

          children = tree[:children] || []
          children.each_with_index do |child, index|
            child_is_last = (index == children.size - 1)
            each_tree_node(child, depth: depth + 1, is_last: child_is_last, &block)
          end
        end

        # Generate the tree connector prefix for a node.
        # @param depth [Integer] Node depth (0 = root, no prefix)
        # @param is_last [Boolean] Whether this node is the last sibling
        # @return [String] Tree connector string with ANSI colors
        def tree_prefix(depth, is_last)
          return "" if depth == 0

          connector = is_last ? TREE_CONNECTOR_LAST : TREE_CONNECTOR_BRANCH
          "#{TREE_COLOR}#{connector}#{RESET_COLOR}"
        end

        # Generate the indentation string for a node's children.
        # @param depth [Integer] Current depth
        # @param parent_is_last_flags [Array<Boolean>] Array of is_last flags for each ancestor
        # @return [String] Indentation string with ANSI colors
        def tree_indent(depth, parent_is_last_flags)
          return "" if depth == 0 || parent_is_last_flags.empty?

          indent_char = parent_is_last_flags.last ? TREE_INDENT_EMPTY : TREE_INDENT_BAR
          "#{TREE_COLOR}#{indent_char}#{RESET_COLOR}"
        end
      end
    end
  end
end
