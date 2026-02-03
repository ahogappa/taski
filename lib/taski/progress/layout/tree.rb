# frozen_string_literal: true

require_relative "base"
require_relative "../template/default"

module Taski
  module Progress
    module Layout
      # Tree layout for hierarchical task display.
      # Renders tasks in a tree structure with visual connectors (├──, └──, │).
      #
      # Output format:
      #   ├── [START] DatabaseSection
      #   │   ├── [START] CreateTable
      #   │   ├── [DONE] CreateTable (45ms)
      #   │   └── [START] MigrateData
      #   └── [START] ApiSection
      #       ├── [DONE] SetupRoutes (12ms)
      #       └── [FAIL] AuthHandler: Connection refused
      #
      # The tree structure (prefixes) is added by this Layout.
      # The task content ([START], [DONE], [FAIL], etc.) comes from the Template.
      #
      # This demonstrates the Template/Layout separation:
      # - Template defines "what one line looks like" (task_start, task_success, etc.)
      # - Layout defines "how lines are arranged" (tree structure, prefixes)
      #
      # @example Using with Template::Default
      #   layout = Taski::Progress::Layout::Tree.new(template: Taski::Progress::Template::Default.new)
      class Tree < Base
        # Tree connector characters
        BRANCH = "├── "
        LAST_BRANCH = "└── "
        VERTICAL = "│   "
        SPACE = "    "

        def initialize(output: $stderr, template: nil)
          template ||= Template::Default.new
          super
          @tree_nodes = {}
          @node_depths = {}
          @node_is_last = {}
        end

        protected

        def on_root_task_set
          build_tree_structure
        end

        def on_task_updated(task_class, state, duration, error)
          text = render_for_task_event(task_class, state, duration, error)
          return unless text

          prefix = build_tree_prefix(task_class)
          output_line("#{prefix}#{text}")
        end

        def on_group_updated(task_class, group_name, state, duration, error)
          text = render_for_group_event(task_class, group_name, state, duration, error)
          return unless text

          prefix = build_tree_prefix(task_class)
          output_line("#{prefix}#{text}")
        end

        def on_start
          return unless @root_task_class
          output_line(render_execution_started(@root_task_class))
        end

        private

        def build_tree_structure
          return unless @root_task_class

          tree = build_tree_node(@root_task_class)
          register_tree_nodes(tree, depth: 0, is_last: true, ancestors_last: [])
          collect_section_candidates(tree)
        end

        def register_tree_nodes(node, depth:, is_last:, ancestors_last:)
          return unless node

          task_class = node[:task_class]
          @tasks[task_class] ||= TaskState.new
          @tree_nodes[task_class] = node
          @node_depths[task_class] = depth
          @node_is_last[task_class] = {is_last: is_last, ancestors_last: ancestors_last.dup}

          children = node[:children]
          children.each_with_index do |child, index|
            child_is_last = (index == children.size - 1)
            new_ancestors_last = ancestors_last + [is_last]
            register_tree_nodes(child, depth: depth + 1, is_last: child_is_last, ancestors_last: new_ancestors_last)
          end
        end

        def collect_section_candidates(node)
          return unless node

          task_class = node[:task_class]

          if node[:is_section]
            candidate_nodes = node[:children].select { |c| c[:is_impl_candidate] }
            candidates = candidate_nodes.map { |c| c[:task_class] }
            @section_candidates[task_class] = candidates unless candidates.empty?

            subtrees = {}
            candidate_nodes.each { |c| subtrees[c[:task_class]] = c }
            @section_candidate_subtrees[task_class] = subtrees unless subtrees.empty?
          end

          node[:children].each { |child| collect_section_candidates(child) }
        end

        def build_tree_prefix(task_class)
          depth = @node_depths[task_class]
          return "" if depth.nil? || depth == 0

          last_info = @node_is_last[task_class]
          return "" unless last_info

          ancestors_last = last_info[:ancestors_last]
          is_last = last_info[:is_last]

          prefix = ""
          # Skip the first ancestor (root) since root has no visual prefix
          # ancestors_last[0] is root's is_last, which we don't display
          ancestors_last[1..].each do |ancestor_is_last|
            prefix += ancestor_is_last ? SPACE : VERTICAL
          end

          prefix += is_last ? LAST_BRANCH : BRANCH
          prefix
        end
      end
    end
  end
end
