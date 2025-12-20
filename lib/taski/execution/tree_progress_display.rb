# frozen_string_literal: true

require "monitor"
require "stringio"

module Taski
  module Execution
    # Tree-based progress display that shows task execution in a tree structure
    # similar to Task.tree, with real-time status updates and stdout capture.
    class TreeProgressDisplay
      SPINNER_FRAMES = %w[⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏].freeze

      # ANSI color codes (matching Task.tree)
      COLORS = {
        reset: "\e[0m",
        task: "\e[32m",      # green
        section: "\e[34m",   # blue
        impl: "\e[33m",      # yellow
        tree: "\e[90m",      # gray
        name: "\e[1m",       # bold
        success: "\e[32m",   # green
        error: "\e[31m",     # red
        running: "\e[36m",   # cyan
        pending: "\e[90m",   # gray
        dim: "\e[2m"         # dim
      }.freeze

      # Status icons
      ICONS = {
        # Run lifecycle states
        pending: "⏸",        # Pause for waiting
        running_prefix: "",  # Will use spinner
        completed: "✓",
        failed: "✗",
        skipped: "⊘",        # Prohibition sign for unselected impl candidates
        # Clean lifecycle states
        cleaning_prefix: "",  # Will use spinner
        clean_completed: "♻",
        clean_failed: "✗"
      }.freeze

      # Shared helper methods
      def self.section_class?(klass)
        defined?(Taski::Section) && klass < Taski::Section
      end

      def self.nested_class?(child_class, parent_class)
        child_name = child_class.name.to_s
        parent_name = parent_class.name.to_s
        child_name.start_with?("#{parent_name}::")
      end

      # Build a tree structure from a root task class.
      # This is the shared tree building logic used by both static and progress display.
      #
      # @param task_class [Class] The task class to build tree for
      # @param ancestors [Set] Set of ancestor task classes for circular detection
      # @return [Hash, nil] Tree node hash or nil if circular
      #
      # Tree node structure:
      #   {
      #     task_class: Class,       # The task class
      #     is_section: Boolean,     # Whether this is a Section
      #     is_circular: Boolean,    # Whether this is a circular reference
      #     is_impl_candidate: Boolean, # Whether this is an impl candidate
      #     children: Array<Hash>    # Child nodes
      #   }
      def self.build_tree_node(task_class, ancestors = Set.new)
        is_circular = ancestors.include?(task_class)

        node = {
          task_class: task_class,
          is_section: section_class?(task_class),
          is_circular: is_circular,
          is_impl_candidate: false,
          children: []
        }

        # Don't traverse children for circular references
        return node if is_circular

        new_ancestors = ancestors + [task_class]
        dependencies = StaticAnalysis::Analyzer.analyze(task_class).to_a
        is_section = section_class?(task_class)

        dependencies.each do |dep|
          child_node = build_tree_node(dep, new_ancestors)
          child_node[:is_impl_candidate] = is_section && nested_class?(dep, task_class)
          node[:children] << child_node
        end

        node
      end

      # Render a static tree structure for a task class (used by Task.tree)
      # @param root_task_class [Class] The root task class
      # @return [String] The rendered tree string
      def self.render_static_tree(root_task_class)
        tree = build_tree_node(root_task_class)
        formatter = StaticTreeFormatter.new
        formatter.format(tree)
      end

      # Formatter for static tree display (no progress tracking, uses task numbers)
      class StaticTreeFormatter
        def format(tree)
          @task_index_map = {}
          format_node(tree, "", false)
        end

        private

        def format_node(node, prefix, is_impl)
          task_class = node[:task_class]
          type_label = colored_type_label(task_class)
          impl_prefix = is_impl ? "#{COLORS[:impl]}[impl]#{COLORS[:reset]} " : ""
          task_number = get_task_number(task_class)
          name = "#{COLORS[:name]}#{task_class.name}#{COLORS[:reset]}"

          if node[:is_circular]
            circular_marker = "#{COLORS[:impl]}(circular)#{COLORS[:reset]}"
            return "#{impl_prefix}#{task_number} #{name} #{type_label} #{circular_marker}\n"
          end

          result = "#{impl_prefix}#{task_number} #{name} #{type_label}\n"

          # Register task number if not already registered
          @task_index_map[task_class] = @task_index_map.size + 1 unless @task_index_map.key?(task_class)

          node[:children].each_with_index do |child, index|
            is_last = (index == node[:children].size - 1)
            result += format_child_branch(child, prefix, is_last)
          end

          result
        end

        def format_child_branch(child, prefix, is_last)
          connector = is_last ? "└── " : "├── "
          extension = is_last ? "    " : "│   "
          child_tree = format_node(child, "#{prefix}#{extension}", child[:is_impl_candidate])

          result = "#{prefix}#{COLORS[:tree]}#{connector}#{COLORS[:reset]}"
          lines = child_tree.lines
          result += lines.first
          lines.drop(1).each { |line| result += line }
          result
        end

        def get_task_number(task_class)
          number = @task_index_map[task_class] || (@task_index_map.size + 1)
          "#{COLORS[:tree]}[#{number}]#{COLORS[:reset]}"
        end

        def colored_type_label(klass)
          if TreeProgressDisplay.section_class?(klass)
            "#{COLORS[:section]}(Section)#{COLORS[:reset]}"
          else
            "#{COLORS[:task]}(Task)#{COLORS[:reset]}"
          end
        end
      end

      class TaskProgress
        attr_accessor :state, :start_time, :end_time, :error, :duration
        attr_accessor :is_impl_candidate

        def initialize
          @state = :pending
          @start_time = nil
          @end_time = nil
          @error = nil
          @duration = nil
          @is_impl_candidate = false
        end
      end

      def initialize(output: $stdout)
        @output = output
        @tasks = {}
        @monitor = Monitor.new
        @spinner_index = 0
        @renderer_thread = nil
        @running = false
        @nest_level = 0 # Track nested executor calls
        @root_task_class = nil
        @tree_structure = nil
        @section_impl_map = {}  # Section -> selected impl class
        @output_capture = nil  # ThreadOutputCapture for getting task output
      end

      # Set the output capture for getting task output
      # @param capture [ThreadOutputCapture] The output capture instance
      def set_output_capture(capture)
        @monitor.synchronize do
          @output_capture = capture
        end
      end

      # Set the root task to build tree structure
      # Only sets root task if not already set (prevents nested executor overwrite)
      # @param root_task_class [Class] The root task class
      def set_root_task(root_task_class)
        @monitor.synchronize do
          return if @root_task_class # Don't overwrite existing root task
          @root_task_class = root_task_class
          build_tree_structure
        end
      end

      # Register which impl was selected for a section
      # @param section_class [Class] The section class
      # @param impl_class [Class] The selected implementation class
      def register_section_impl(section_class, impl_class)
        @monitor.synchronize do
          @section_impl_map[section_class] = impl_class
        end
      end

      # @param task_class [Class] The task class to register
      def register_task(task_class)
        @monitor.synchronize do
          return if @tasks.key?(task_class)
          @tasks[task_class] = TaskProgress.new
        end
      end

      # @param task_class [Class] The task class to check
      # @return [Boolean] true if the task is registered
      def task_registered?(task_class)
        @monitor.synchronize do
          @tasks.key?(task_class)
        end
      end

      # @param task_class [Class] The task class to update
      # @param state [Symbol] The new state (:pending, :running, :completed, :failed)
      # @param duration [Float] Duration in milliseconds (for completed tasks)
      # @param error [Exception] Error object (for failed tasks)
      def update_task(task_class, state:, duration: nil, error: nil)
        @monitor.synchronize do
          progress = @tasks[task_class]
          return unless progress

          progress.state = state
          progress.duration = duration if duration
          progress.error = error if error

          case state
          when :running
            progress.start_time = Time.now
          when :completed, :failed
            progress.end_time = Time.now
          end
        end
      end

      # @param task_class [Class] The task class
      # @return [Symbol] The task state
      def task_state(task_class)
        @monitor.synchronize do
          @tasks[task_class]&.state
        end
      end

      def start
        should_start = false
        @monitor.synchronize do
          @nest_level += 1
          return if @nest_level > 1 # Already running from outer executor
          return if @running
          return unless @output.tty?

          @running = true
          should_start = true
        end

        return unless should_start

        @output.print "\e[?25l"  # Hide cursor
        @output.print "\e7"      # Save cursor position (before any tree output)
        @renderer_thread = Thread.new do
          loop do
            break unless @running
            render_live
            sleep 0.1
          end
        end
      end

      def stop
        should_stop = false
        @monitor.synchronize do
          @nest_level -= 1 if @nest_level > 0
          return unless @nest_level == 0
          return unless @running

          @running = false
          should_stop = true
        end

        return unless should_stop

        @renderer_thread&.join
        @output.print "\e[?25h"  # Show cursor
        render_final
      end

      private

      # Build tree structure from root task for display
      def build_tree_structure
        return unless @root_task_class

        @tree_structure = self.class.build_tree_node(@root_task_class)
        register_tasks_from_tree(@tree_structure)
      end

      # Register all tasks from tree structure
      def register_tasks_from_tree(node)
        return unless node

        task_class = node[:task_class]
        register_task(task_class)

        # Mark as impl candidate if applicable
        if node[:is_impl_candidate]
          @tasks[task_class].is_impl_candidate = true
        end

        node[:children].each { |child| register_tasks_from_tree(child) }
      end

      def render_live
        # Poll for new output from task pipes
        @output_capture&.poll

        lines = nil

        @monitor.synchronize do
          @spinner_index += 1
          lines = build_tree_display
        end

        return if lines.nil? || lines.empty?

        # Restore cursor to saved position (from start) and clear
        @output.print "\e8"  # Restore cursor position
        @output.print "\e[J" # Clear from cursor to end of screen

        # Redraw all lines
        lines.each do |line|
          @output.print "#{line}\n"
        end

        @output.flush
      end

      def render_final
        @monitor.synchronize do
          lines = build_tree_display
          return if lines.empty?

          # Restore cursor to saved position (from start) and clear
          @output.print "\e8"  # Restore cursor position
          @output.print "\e[J" # Clear from cursor to end of screen

          # Print final state
          lines.each { |line| @output.puts line }
        end
      end

      # Build display lines from tree structure
      def build_tree_display
        return [] unless @tree_structure

        lines = []
        build_root_tree_lines(@tree_structure, "", lines)
        lines
      end

      # Build tree lines starting from root node
      # @param node [Hash] Tree node (root)
      # @param prefix [String] Line prefix for tree drawing
      # @param lines [Array<String>] Accumulated output lines
      def build_root_tree_lines(node, prefix, lines)
        task_class = node[:task_class]
        progress = @tasks[task_class]

        # Root node is never an impl candidate and is always selected
        line = format_tree_line(task_class, progress, false, true)
        lines << "#{prefix}#{line}"

        render_children(node, prefix, lines, task_class, true)
      end

      # Render all children of a node recursively
      # @param node [Hash] Tree node
      # @param prefix [String] Line prefix for tree drawing
      # @param lines [Array<String>] Accumulated output lines
      # @param parent_task_class [Class] Parent task class (for impl selection lookup)
      # @param ancestor_selected [Boolean] Whether all ancestor impl candidates were selected
      def render_children(node, prefix, lines, parent_task_class, ancestor_selected)
        children = node[:children]
        children.each_with_index do |child, index|
          is_last = (index == children.size - 1)
          connector = is_last ? "└── " : "├── "
          extension = is_last ? "    " : "│   "

          child_progress = @tasks[child[:task_class]]

          # Determine child's selection status
          child_is_selected = true
          if child[:is_impl_candidate]
            selected_impl = @section_impl_map[parent_task_class]
            child_is_selected = (selected_impl == child[:task_class])
          end
          # Propagate ancestor selection state
          child_effective_selected = ancestor_selected && child_is_selected

          child_line = format_tree_line(
            child[:task_class],
            child_progress,
            child[:is_impl_candidate],
            child_effective_selected
          )
          lines << "#{prefix}#{COLORS[:tree]}#{connector}#{COLORS[:reset]}#{child_line}"

          if child[:children].any?
            render_children(child, "#{prefix}#{COLORS[:tree]}#{extension}#{COLORS[:reset]}", lines, child[:task_class], child_effective_selected)
          end
        end
      end

      def format_tree_line(task_class, progress, is_impl, is_selected)
        return format_unknown_task(task_class, is_selected) unless progress

        type_label = type_label_for(task_class, is_selected)
        impl_prefix = is_impl ? "#{COLORS[:impl]}[impl]#{COLORS[:reset]} " : ""

        # Handle unselected nodes (either impl candidates or children of unselected impl)
        # Show dimmed regardless of task state since they belong to unselected branch
        unless is_selected
          name = "#{COLORS[:dim]}#{task_class.name}#{COLORS[:reset]}"
          suffix = is_impl ? " #{COLORS[:dim]}(not selected)#{COLORS[:reset]}" : ""
          return "#{COLORS[:dim]}#{ICONS[:skipped]}#{COLORS[:reset]} #{impl_prefix}#{name} #{type_label}#{suffix}"
        end

        status_icon = task_status_icon(progress.state, is_selected)
        name = "#{COLORS[:name]}#{task_class.name}#{COLORS[:reset]}"
        details = task_details(progress)
        output_suffix = task_output_suffix(task_class, progress.state)

        "#{status_icon} #{impl_prefix}#{name} #{type_label}#{details}#{output_suffix}"
      end

      def format_unknown_task(task_class, is_selected = true)
        if is_selected
          name = "#{COLORS[:name]}#{task_class.name}#{COLORS[:reset]}"
          type_label = type_label_for(task_class, true)
          "#{COLORS[:pending]}#{ICONS[:pending]}#{COLORS[:reset]} #{name} #{type_label}"
        else
          name = "#{COLORS[:dim]}#{task_class.name}#{COLORS[:reset]}"
          type_label = type_label_for(task_class, false)
          "#{COLORS[:dim]}#{ICONS[:skipped]}#{COLORS[:reset]} #{name} #{type_label}"
        end
      end

      ##
      # Maps a task state and selection flag to an ANSI-colored status icon string.
      # @param [Symbol] state - The task lifecycle state (:pending, :running, :completed, :failed, :cleaning, :clean_completed, :clean_failed).
      # @param [Boolean] is_selected - Whether the task is selected for display; when false a dimmed skipped icon is returned.
      # @return [String] The ANSI-colored icon or spinner character representing the task's current status.
      def task_status_icon(state, is_selected)
        # If not selected (either direct impl candidate or child of unselected), show skipped
        unless is_selected
          return "#{COLORS[:dim]}#{ICONS[:skipped]}#{COLORS[:reset]}"
        end

        case state
        # Run lifecycle states
        when :completed
          "#{COLORS[:success]}#{ICONS[:completed]}#{COLORS[:reset]}"
        when :failed
          "#{COLORS[:error]}#{ICONS[:failed]}#{COLORS[:reset]}"
        when :running
          "#{COLORS[:running]}#{spinner_char}#{COLORS[:reset]}"
        # Clean lifecycle states
        when :cleaning
          "#{COLORS[:running]}#{spinner_char}#{COLORS[:reset]}"
        when :clean_completed
          "#{COLORS[:success]}#{ICONS[:clean_completed]}#{COLORS[:reset]}"
        when :clean_failed
          "#{COLORS[:error]}#{ICONS[:clean_failed]}#{COLORS[:reset]}"
        else
          "#{COLORS[:pending]}#{ICONS[:pending]}#{COLORS[:reset]}"
        end
      end

      def spinner_char
        SPINNER_FRAMES[@spinner_index % SPINNER_FRAMES.length]
      end

      def type_label_for(task_class, is_selected = true)
        if section_class?(task_class)
          is_selected ? "#{COLORS[:section]}(Section)#{COLORS[:reset]}" : "#{COLORS[:dim]}(Section)#{COLORS[:reset]}"
        else
          is_selected ? "#{COLORS[:task]}(Task)#{COLORS[:reset]}" : "#{COLORS[:dim]}(Task)#{COLORS[:reset]}"
        end
      end

      ##
      # Formats a short status string for a task based on its lifecycle state.
      # @param [TaskProgress] progress - Progress object with `state`, `start_time`, and `duration`.
      # @return [String] A terminal-ready status fragment (may include ANSI color codes) such as durations, "failed", "cleaning ..." or an empty string when no detail applies.
      def task_details(progress)
        case progress.state
        # Run lifecycle states
        when :completed
          " #{COLORS[:success]}(#{progress.duration}ms)#{COLORS[:reset]}"
        when :failed
          " #{COLORS[:error]}(failed)#{COLORS[:reset]}"
        when :running
          elapsed = ((Time.now - progress.start_time) * 1000).round(0)
          " #{COLORS[:running]}(#{elapsed}ms)#{COLORS[:reset]}"
        # Clean lifecycle states
        when :cleaning
          elapsed = ((Time.now - progress.start_time) * 1000).round(0)
          " #{COLORS[:running]}(cleaning #{elapsed}ms)#{COLORS[:reset]}"
        when :clean_completed
          " #{COLORS[:success]}(cleaned #{progress.duration}ms)#{COLORS[:reset]}"
        when :clean_failed
          " #{COLORS[:error]}(clean failed)#{COLORS[:reset]}"
        else
          ""
        end
      end

      # Get task output suffix to display next to task
      ##
      # Produces a trailing output suffix for a task when it is actively producing output.
      #
      # Fetches the last captured stdout/stderr line for the given task and returns a
      # formatted, dimmed suffix containing that line only when the task `state` is
      # `:running` or `:cleaning` and an output capture is available. The returned
      # string is truncated to fit the terminal width (with a minimum visible length)
      # and includes surrounding dim/reset color codes.
      # @param [Class] task_class - The task class whose output to query.
      # @param [Symbol] state - The task lifecycle state (only `:running` and `:cleaning` produce output).
      # @return [String] A formatted, possibly truncated output suffix prefixed with a dim pipe, or an empty string when no output should be shown.
      def task_output_suffix(task_class, state)
        return "" unless state == :running || state == :cleaning
        return "" unless @output_capture

        last_line = @output_capture.last_line_for(task_class)
        return "" unless last_line && !last_line.empty?

        # Truncate if too long (leave space for tree structure)
        terminal_cols = terminal_width
        max_output_length = terminal_cols - 50
        max_output_length = 20 if max_output_length < 20

        truncated = if last_line.length > max_output_length
          last_line[0, max_output_length - 3] + "..."
        else
          last_line
        end

        " #{COLORS[:dim]}| #{truncated}#{COLORS[:reset]}"
      end

      def terminal_width
        if @output.respond_to?(:winsize)
          _, cols = @output.winsize
          cols || 80
        else
          80
        end
      end

      def section_class?(klass)
        self.class.section_class?(klass)
      end

      def nested_class?(child_class, parent_class)
        self.class.nested_class?(child_class, parent_class)
      end
    end
  end
end
