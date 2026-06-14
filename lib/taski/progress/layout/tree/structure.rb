# frozen_string_literal: true

module Taski
  module Progress
    module Layout
      module Tree
        # Shared tree structure logic for Tree::Live and Tree::Event.
        # Provides tree building, node registration, prefix generation,
        # and tree rendering methods.
        module Structure
          # Tree connector characters
          BRANCH = "├── "
          LAST_BRANCH = "└── "
          VERTICAL = "│   "
          SPACE = "    "

          # Returns the tree structure as a string.
          # Uses the current theme to render task content for each node.
          def render_tree
            build_tree_lines.join("\n") + "\n"
          end

          protected

          def init_tree_structure
            @tree_nodes = {}
            @node_prefixes = {}
          end

          # Drop the previous execution's tree when a new top-level execution
          # reuses this display; handle_ready then rebuilds it for the new root.
          def handle_reset
            init_tree_structure
            super
          end

          def build_ready_tree
            graph = context&.dependency_graph
            root = context&.root_task_class
            return unless graph && root

            tree = build_tree_from_graph(root, graph)
            register_tree_nodes(tree, depth: 0, is_last: true, ancestors_last: [])
          end

          # Output text with tree prefix for the given task
          def output_with_prefix(task_class, text)
            prefix = build_tree_prefix(task_class)
            output_line("#{prefix}#{text}")
          end

          private

          def build_tree_from_graph(task_class, graph, ancestors = Set.new)
            is_circular = ancestors.include?(task_class)
            node = {task_class: task_class, is_circular: is_circular, children: []}
            return node if is_circular

            new_ancestors = ancestors + [task_class]
            deps = graph.dependencies_for(task_class)
            deps.each do |dep|
              child_node = build_tree_from_graph(dep, graph, new_ancestors)
              node[:children] << child_node
            end
            node
          end

          def register_tree_nodes(node, depth:, is_last:, ancestors_last:)
            return unless node

            task_class = node[:task_class]
            @tasks[task_class] ||= new_task_progress
            @tree_nodes[task_class] ||= node

            # A shared dependency is registered once per occurrence in the
            # tree. The prefix belongs to the OCCURRENCE (stored on the node),
            # not to the task class — a class-keyed prefix would be clobbered
            # by the last occurrence and corrupt every earlier row. The
            # class-keyed map keeps only the FIRST occurrence, as the one
            # canonical prefix for per-event output lines.
            prefix = compute_tree_prefix(depth: depth, is_last: is_last, ancestors_last: ancestors_last)
            node[:prefix] = prefix
            @node_prefixes[task_class] ||= prefix

            children = node[:children]
            children.each_with_index do |child, index|
              child_is_last = (index == children.size - 1)
              new_ancestors_last = ancestors_last + [is_last]
              register_tree_nodes(child, depth: depth + 1, is_last: child_is_last, ancestors_last: new_ancestors_last)
            end
          end

          def build_tree_lines
            return [] unless @root_task_class

            lines = []
            root_node = @tree_nodes[@root_task_class]
            build_node_lines(root_node, lines)
            lines
          end

          def build_node_lines(node, lines)
            return unless node

            prefix = node[:prefix] || ""
            content = build_task_content(node[:task_class])
            lines << "#{prefix}#{content}"

            node[:children].each do |child|
              build_node_lines(child, lines)
            end
          end

          def build_task_content(task_class)
            progress = @tasks[task_class]

            case progress&.dig(:run_state)
            when :running
              render_task_started(task_class)
            when :completed
              render_task_succeeded(task_class, task_duration: compute_duration(progress, :run))
            when :failed
              render_task_failed(task_class, error: nil)
            when :skipped
              render_task_skipped(task_class)
            else
              task = TaskInfo.new(name: task_class_name(task_class), state: :pending)
              render_theme(:task_pending, task:, execution: execution_info)
            end
          end

          # Canonical (first-occurrence) prefix for a task class, used by
          # per-event output lines in Tree::Event.
          def build_tree_prefix(task_class)
            @node_prefixes[task_class] || ""
          end

          def compute_tree_prefix(depth:, is_last:, ancestors_last:)
            return "" if depth.zero?

            prefix = ""
            # Skip the first ancestor (root) since root has no visual prefix
            ancestors_last[1..].each do |ancestor_is_last|
              prefix += ancestor_is_last ? SPACE : VERTICAL
            end

            prefix + (is_last ? LAST_BRANCH : BRANCH)
          end
        end
      end
    end
  end
end
