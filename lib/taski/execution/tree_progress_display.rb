# frozen_string_literal: true

require "stringio"
require_relative "base_progress_display"

module Taski
  module Execution
    # Tree-based progress display that shows task execution in a tree structure
    # similar to Task.tree, with real-time status updates and stdout capture.
    class TreeProgressDisplay < BaseProgressDisplay
      SPINNER_FRAMES = %w[⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏].freeze

      # Output display settings
      OUTPUT_RESERVED_WIDTH = 30  # Characters reserved for tree structure
      OUTPUT_MIN_LENGTH = 70      # Minimum visible output length
      OUTPUT_SEPARATOR = " > "      # Separator before task output
      GROUP_SEPARATOR = " | "       # Separator between group name and task name
      TRUNCATION_ELLIPSIS = "..." # Ellipsis for truncated output

      # Display settings
      RENDER_INTERVAL = 0.1       # Seconds between display updates
      DEFAULT_TERMINAL_WIDTH = 80 # Default terminal width when unknown

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

      ##
      # Checks if a class is a Taski::Section subclass.
      # @param klass [Class] The class to check.
      # @return [Boolean] true if the class is a Section.
      def self.section_class?(klass)
        defined?(Taski::Section) && klass < Taski::Section
      end

      ##
      # Checks if a class is nested within another class by name prefix.
      # @param child_class [Class] The potential nested class.
      # @param parent_class [Class] The potential parent class.
      # @return [Boolean] true if child_class name starts with parent_class name and "::".
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

      def initialize(output: $stdout)
        super
        @spinner_index = 0
        @renderer_thread = nil
        @running = false
        @tree_structure = nil
        @section_impl_map = {}  # Section -> selected impl class
        @last_line_count = 0  # Track number of lines drawn for cursor movement
      end

      protected

      # Template method: Called when root task is set
      def on_root_task_set
        build_tree_structure
      end

      # Template method: Called when a section impl is registered
      def on_section_impl_registered(section_class, impl_class)
        @section_impl_map[section_class] = impl_class
      end

      # Template method: Determine if display should activate
      def should_activate?
        tty?
      end

      # Template method: Called when display starts
      def on_start
        @running = true
        @output.print "\e[?1049h" # Switch to alternate screen buffer
        @output.print "\e[H"      # Move cursor to home (top-left)
        @output.print "\e[?25l"   # Hide cursor
        @renderer_thread = Thread.new do
          loop do
            break unless @running
            render_live
            sleep RENDER_INTERVAL
          end
        end
      end

      # Template method: Called when display stops
      def on_stop
        @running = false
        @renderer_thread&.join
        @output.print "\e[?25h"   # Show cursor
        @output.print "\e[?1049l" # Switch back to main screen buffer
        render_final
      end

      private

      # Build tree structure from root task for display
      def build_tree_structure
        return unless @root_task_class

        @tree_structure = self.class.build_tree_node(@root_task_class)
        register_tasks_from_tree(@tree_structure)
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

        # Move cursor up by the number of lines previously drawn
        if @last_line_count > 0
          @output.print "\e[#{@last_line_count}A"  # Move cursor up n lines
        end
        @output.print "\e[J"  # Clear from cursor to end of screen

        # Redraw all lines
        lines.each do |line|
          @output.print "#{line}\n"
        end

        @last_line_count = lines.size
        @output.flush
      end

      def render_final
        @monitor.synchronize do
          return unless @root_task_class

          root_progress = @tasks[@root_task_class]
          return unless root_progress

          # Print single summary line instead of full tree
          @output.puts build_summary_line(@root_task_class, root_progress)
        end
      end

      def build_summary_line(task_class, progress)
        # Determine overall status and icon
        if progress.run_state == :failed || progress.clean_state == :clean_failed
          icon = "#{COLORS[:error]}#{ICONS[:failed]}#{COLORS[:reset]}"
          status = "#{COLORS[:error]}failed#{COLORS[:reset]}"
        else
          icon = "#{COLORS[:success]}#{ICONS[:completed]}#{COLORS[:reset]}"
          status = "#{COLORS[:success]}completed#{COLORS[:reset]}"
        end

        name = "#{COLORS[:name]}#{task_class.name}#{COLORS[:reset]}"

        # Calculate total duration
        duration_str = ""
        if progress.run_duration
          duration_str = " (#{progress.run_duration}ms)"
        end

        # Count completed tasks
        completed_count = @tasks.values.count { |p| p.run_state == :completed }
        total_count = @tasks.values.count { |p| p.run_state != :pending || p == progress }
        task_count_str = " [#{completed_count}/#{total_count} tasks]"

        "#{icon} #{name} #{status}#{duration_str}#{task_count_str}"
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

        status_icons = combined_status_icons(progress)
        name = "#{COLORS[:name]}#{task_class.name}#{COLORS[:reset]}"
        details = combined_task_details(progress)
        output_suffix = task_output_suffix(task_class, progress.state)

        "#{status_icons} #{impl_prefix}#{name} #{type_label}#{details}#{output_suffix}"
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
      # Returns combined status icons for both run and clean phases.
      # Shows run icon first, then clean icon if clean phase has started.
      # @param [TaskProgress] progress - The task progress object with run_state and clean_state.
      # @return [String] The combined ANSI-colored icons.
      def combined_status_icons(progress)
        run_icon = run_status_icon(progress.run_state)

        # If clean phase hasn't started, only show run icon
        return run_icon unless progress.clean_state

        clean_icon = clean_status_icon(progress.clean_state)
        "#{run_icon} #{clean_icon}"
      end

      ##
      # Returns the status icon for run phase.
      # @param [Symbol] state - The run state (:pending, :running, :completed, :failed).
      # @return [String] The ANSI-colored icon.
      def run_status_icon(state)
        case state
        when :completed
          "#{COLORS[:success]}#{ICONS[:completed]}#{COLORS[:reset]}"
        when :failed
          "#{COLORS[:error]}#{ICONS[:failed]}#{COLORS[:reset]}"
        when :running
          "#{COLORS[:running]}#{spinner_char}#{COLORS[:reset]}"
        else
          "#{COLORS[:pending]}#{ICONS[:pending]}#{COLORS[:reset]}"
        end
      end

      ##
      # Returns the status icon for clean phase.
      # @param [Symbol] state - The clean state (:cleaning, :clean_completed, :clean_failed).
      # @return [String] The ANSI-colored icon.
      def clean_status_icon(state)
        case state
        when :cleaning
          "#{COLORS[:running]}#{spinner_char}#{COLORS[:reset]}"
        when :clean_completed
          "#{COLORS[:success]}#{ICONS[:clean_completed]}#{COLORS[:reset]}"
        when :clean_failed
          "#{COLORS[:error]}#{ICONS[:clean_failed]}#{COLORS[:reset]}"
        else
          ""
        end
      end

      ##
      # Returns the current spinner character for animation.
      # Cycles through SPINNER_FRAMES based on the current spinner index.
      # @return [String] The current spinner frame character.
      def spinner_char
        SPINNER_FRAMES[@spinner_index % SPINNER_FRAMES.length]
      end

      ##
      # Returns a colored type label for the task class.
      # @param task_class [Class] The task class to get the label for.
      # @param is_selected [Boolean] Whether the task is selected (affects color).
      # @return [String] The colored type label (Section or Task).
      def type_label_for(task_class, is_selected = true)
        if section_class?(task_class)
          is_selected ? "#{COLORS[:section]}(Section)#{COLORS[:reset]}" : "#{COLORS[:dim]}(Section)#{COLORS[:reset]}"
        else
          is_selected ? "#{COLORS[:task]}(Task)#{COLORS[:reset]}" : "#{COLORS[:dim]}(Task)#{COLORS[:reset]}"
        end
      end

      ##
      # Returns combined details for both run and clean phases.
      # @param [TaskProgress] progress - Progress object with run_state, clean_state, etc.
      # @return [String] Combined details for both phases.
      def combined_task_details(progress)
        run_detail = run_phase_details(progress)
        clean_detail = clean_phase_details(progress)

        if clean_detail.empty?
          run_detail
        else
          "#{run_detail}#{clean_detail}"
        end
      end

      ##
      # Returns details for the run phase only.
      # @param [TaskProgress] progress - Progress object.
      # @return [String] Run phase details.
      def run_phase_details(progress)
        case progress.run_state
        when :completed
          return "" unless progress.run_duration
          " #{COLORS[:success]}(#{progress.run_duration}ms)#{COLORS[:reset]}"
        when :failed
          " #{COLORS[:error]}(failed)#{COLORS[:reset]}"
        when :running
          return "" unless progress.run_start_time
          elapsed = ((Time.now - progress.run_start_time) * 1000).round(0)
          " #{COLORS[:running]}(#{elapsed}ms)#{COLORS[:reset]}"
        else
          ""
        end
      end

      ##
      # Returns details for the clean phase only.
      # @param [TaskProgress] progress - Progress object.
      # @return [String] Clean phase details.
      def clean_phase_details(progress)
        case progress.clean_state
        when :cleaning
          return "" unless progress.clean_start_time
          elapsed = ((Time.now - progress.clean_start_time) * 1000).round(0)
          " #{COLORS[:running]}(cleaning #{elapsed}ms)#{COLORS[:reset]}"
        when :clean_completed
          return "" unless progress.clean_duration
          " #{COLORS[:success]}(cleaned #{progress.clean_duration}ms)#{COLORS[:reset]}"
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

        # Get current group name if any
        progress = @tasks[task_class]
        group_prefix = ""
        if progress&.current_group_index
          current_group = progress.groups[progress.current_group_index]
          group_prefix = "#{current_group.name}#{GROUP_SEPARATOR}" if current_group
        end

        # Truncate if too long (leave space for tree structure)
        terminal_cols = terminal_width
        max_output_length = terminal_cols - OUTPUT_RESERVED_WIDTH
        max_output_length = OUTPUT_MIN_LENGTH if max_output_length < OUTPUT_MIN_LENGTH

        full_output = "#{group_prefix}#{last_line}"
        truncated = if full_output.length > max_output_length
          full_output[0, max_output_length - TRUNCATION_ELLIPSIS.length] + TRUNCATION_ELLIPSIS
        else
          full_output
        end

        "#{COLORS[:dim]}#{OUTPUT_SEPARATOR}#{truncated}#{COLORS[:reset]}"
      end

      ##
      # Returns the terminal width in columns.
      # Defaults to 80 if the output IO doesn't support winsize.
      # @return [Integer] The terminal width in columns.
      def terminal_width
        if @output.respond_to?(:winsize)
          _, cols = @output.winsize
          cols || DEFAULT_TERMINAL_WIDTH
        else
          DEFAULT_TERMINAL_WIDTH
        end
      end

      ##
      # Checks if a class is a Taski::Section subclass.
      # Delegates to the class method.
      # @param klass [Class] The class to check.
      # @return [Boolean] true if the class is a Section.
      def section_class?(klass)
        self.class.section_class?(klass)
      end

      ##
      # Checks if a class is nested within another class.
      # Delegates to the class method.
      # @param child_class [Class] The potential nested class.
      # @param parent_class [Class] The potential parent class.
      # @return [Boolean] true if child_class is nested within parent_class.
      def nested_class?(child_class, parent_class)
        self.class.nested_class?(child_class, parent_class)
      end
    end
  end
end
