# frozen_string_literal: true

require_relative "base"
require_relative "../template/tree"

module Taski
  module Progress
    module Layout
      # Tree layout for hierarchical task display.
      # Renders tasks in a tree structure with visual connectors (├──, └──, │).
      #
      # Operates in two modes:
      # - TTY mode: Periodic full-tree refresh with spinner animation
      # - Non-TTY mode: Incremental output with tree prefixes (for logs/tests)
      #
      # Output format (live updating):
      #   BuildApplication
      #   ├── ⠹ DatabaseSection
      #   │   ├── ✓ ProductionDB (50ms)
      #   │   └── ⠹ DevelopmentDB
      #   ├── ○ ExtractLayers
      #   │   ├── ✓ DownloadLayer1 (100ms)
      #   │   └── ○ DownloadLayer2
      #   └── ✓ RunSystemCommand (200ms)
      #
      # The tree structure (prefixes) is added by this Layout.
      # The task content (icons, names, duration) comes from the Template.
      #
      # This demonstrates the Template/Layout separation:
      # - Template defines "what one line looks like" (icons, colors, formatting)
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
          template ||= Template::Tree.new
          super
          @tree_nodes = {}
          @node_depths = {}
          @node_is_last = {}
          @renderer_thread = nil
          @running = false
          @running_mutex = Mutex.new
          @last_line_count = 0
          @non_tty_started = false
        end

        # Override start to handle non-TTY mode
        def start
          @monitor.synchronize do
            @nest_level += 1
            return if @nest_level > 1

            @start_time = Time.now

            if should_activate?
              @active = true
            else
              # Non-TTY mode: output execution start message
              @non_tty_started = true
              output_line(render_execution_started(@root_task_class)) if @root_task_class
            end
          end

          on_start if @active
        end

        # Override stop to handle non-TTY mode
        def stop
          was_active = false
          non_tty_was_started = false
          @monitor.synchronize do
            @nest_level -= 1 if @nest_level > 0
            return unless @nest_level == 0
            was_active = @active
            non_tty_was_started = @non_tty_started
            @active = false
            @non_tty_started = false
          end

          if was_active
            on_stop
          elsif non_tty_was_started
            # Non-TTY mode: output execution summary
            output_execution_summary
          end
          flush_queued_messages
        end

        protected

        def on_root_task_set
          build_tree_structure
        end

        # In TTY mode, tree is updated by render_live periodically.
        # In non-TTY mode, output lines immediately with tree prefix.
        def on_task_updated(task_class, state, duration, error)
          return if @active  # TTY mode: skip per-event output

          # Non-TTY mode: output with tree prefix
          text = render_for_task_event(task_class, state, duration, error)
          output_with_prefix(task_class, text) if text
        end

        def on_group_updated(task_class, group_name, state, duration, error)
          return if @active  # TTY mode: skip per-event output

          # Non-TTY mode: output with tree prefix
          text = render_for_group_event(task_class, group_name, state, duration, error)
          output_with_prefix(task_class, text) if text
        end

        def should_activate?
          force_progress? || tty?
        end

        def on_start
          @running_mutex.synchronize { @running = true }
          start_spinner_timer
          @output.print "\e[?25l" # Hide cursor
          @renderer_thread = Thread.new do
            loop do
              break unless @running_mutex.synchronize { @running }
              render_live
              sleep @template.render_interval
            end
          end
        end

        def on_stop
          @running_mutex.synchronize { @running = false }
          @renderer_thread&.join
          stop_spinner_timer
          @output.print "\e[?25h" # Show cursor
          render_final
        end

        private

        # Output text with tree prefix for the given task
        def output_with_prefix(task_class, text)
          prefix = build_tree_prefix(task_class)
          output_line("#{prefix}#{text}")
        end

        # Output execution summary for non-TTY mode
        def output_execution_summary
          text = if failed_count > 0
            render_execution_failed(failed_count: failed_count, total_count: total_count, total_duration: total_duration)
          else
            render_execution_completed(completed_count: completed_count, total_count: total_count, total_duration: total_duration)
          end
          output_line(text)
        end

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

        def render_live
          @monitor.synchronize do
            lines = build_tree_lines
            clear_previous_output
            lines.each { |line| @output.puts line }
            @output.flush
            @last_line_count = lines.size
          end
        end

        def render_final
          @monitor.synchronize do
            lines = build_tree_lines
            clear_previous_output

            lines.each { |line| @output.puts line }

            # Add summary line
            summary = if failed_count > 0
              render_execution_failed(failed_count: failed_count, total_count: total_count, total_duration: total_duration)
            else
              render_execution_completed(completed_count: completed_count, total_count: total_count, total_duration: total_duration)
            end
            @output.puts summary
            @output.flush
          end
        end

        def clear_previous_output
          return if @last_line_count == 0
          # Move cursor up and clear lines
          @output.print "\e[#{@last_line_count}A\e[J"
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

          task_class = node[:task_class]
          prefix = build_tree_prefix(task_class)
          content = build_task_content(task_class)
          lines << "#{prefix}#{content}"

          node[:children].each do |child|
            build_node_lines(child, lines)
          end
        end

        def build_task_content(task_class)
          task_state = @tasks[task_class]
          name = short_name(task_class)

          case task_state&.run_state
          when :running
            render_task_started(task_class)
          when :completed
            render_task_succeeded(task_class, task_duration: task_state.run_duration)
          when :failed
            render_task_failed(task_class, error: task_state.run_error)
          else
            render_template(:task_pending, task_name: name, state: :pending)
          end
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
