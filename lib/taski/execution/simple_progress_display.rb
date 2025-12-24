# frozen_string_literal: true

require "monitor"

module Taski
  module Execution
    # SimpleProgressDisplay provides a minimalist single-line progress display
    # that shows task execution status in a compact format:
    #
    #   ⠹ [3/5] DeployTask | Uploading files...
    #
    # This is an alternative to TreeProgressDisplay for users who prefer
    # less verbose output.
    class SimpleProgressDisplay
      SPINNER_FRAMES = %w[⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏].freeze
      RENDER_INTERVAL = 0.1

      ICONS = {
        success: "✓",
        failure: "✗",
        pending: "○"
      }.freeze

      COLORS = {
        green: "\e[32m",
        red: "\e[31m",
        yellow: "\e[33m",
        dim: "\e[2m",
        reset: "\e[0m"
      }.freeze

      # Simple task state tracker
      TaskProgress = Struct.new(
        :run_state, :run_start_time, :run_end_time, :run_error, :run_duration,
        :clean_state, :clean_start_time, :clean_end_time, :clean_error, :clean_duration,
        :is_impl_candidate,
        keyword_init: true
      ) do
        def initialize(*)
          super
          self.run_state ||= :pending
          self.clean_state ||= :pending
          self.is_impl_candidate ||= false
        end

        def state
          (clean_state != :pending) ? clean_state : run_state
        end
      end

      def initialize(output: $stdout)
        @output = output
        @tasks = {}
        @monitor = Monitor.new
        @spinner_index = 0
        @renderer_thread = nil
        @running = false
        @nest_level = 0
        @root_task_class = nil
        @output_capture = nil
        @start_time = nil
      end

      def set_output_capture(capture)
        @monitor.synchronize do
          @output_capture = capture
        end
      end

      def set_root_task(root_task_class)
        @monitor.synchronize do
          return if @root_task_class # Don't overwrite existing root task
          @root_task_class = root_task_class
          build_tree_structure
        end
      end

      def register_section_impl(section_class, impl_class)
        @monitor.synchronize do
          # Mark the impl task as selected
          register_task(impl_class)
          if @tasks[impl_class]
            @tasks[impl_class].is_impl_candidate = false
          end
        end
      end

      def register_task(task_class)
        @monitor.synchronize do
          return if @tasks.key?(task_class)
          @tasks[task_class] = TaskProgress.new
        end
      end

      def task_registered?(task_class)
        @monitor.synchronize do
          @tasks.key?(task_class)
        end
      end

      def update_task(task_class, state:, duration: nil, error: nil)
        @monitor.synchronize do
          progress = @tasks[task_class]
          return unless progress

          case state
          # Run lifecycle states
          when :pending
            progress.run_state = :pending
          when :running
            progress.run_state = :running
            progress.run_start_time = Time.now
          when :completed
            progress.run_state = :completed
            progress.run_end_time = Time.now
            progress.run_duration = duration if duration
          when :failed
            progress.run_state = :failed
            progress.run_end_time = Time.now
            progress.run_error = error if error
          # Clean lifecycle states
          when :cleaning
            progress.clean_state = :cleaning
            progress.clean_start_time = Time.now
          when :clean_completed
            progress.clean_state = :clean_completed
            progress.clean_end_time = Time.now
            progress.clean_duration = duration if duration
          when :clean_failed
            progress.clean_state = :clean_failed
            progress.clean_end_time = Time.now
            progress.clean_error = error if error
          end
        end
      end

      def task_state(task_class)
        @monitor.synchronize do
          progress = @tasks[task_class]
          return nil unless progress
          progress.state
        end
      end

      def update_group(task_class, group_name, state:, duration: nil, error: nil)
        # Simple display ignores group updates for now
        # Could be extended to show group name in the output suffix
      end

      def start
        should_start = false
        @monitor.synchronize do
          @nest_level += 1
          return if @nest_level > 1 # Already running from outer executor
          return if @running
          return unless @output.tty?

          @running = true
          @start_time = Time.now
          should_start = true
        end

        return unless should_start

        @output.print "\e[?25l" # Hide cursor
        @renderer_thread = Thread.new do
          loop do
            break unless @running
            render_live
            sleep RENDER_INTERVAL
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
        @output.print "\e[?25h" # Show cursor
        render_final
      end

      private

      def build_tree_structure
        return unless @root_task_class

        # Use TreeProgressDisplay's static method for tree building
        tree = TreeProgressDisplay.build_tree_node(@root_task_class)
        register_tasks_from_tree(tree)
      end

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
        @monitor.synchronize do
          @spinner_index = (@spinner_index + 1) % SPINNER_FRAMES.size
          line = build_status_line
          # Clear line and write new content
          @output.print "\r\e[K#{line}"
          @output.flush
        end
      end

      def render_final
        @monitor.synchronize do
          total_duration = @start_time ? ((Time.now - @start_time) * 1000).to_i : 0
          completed = @tasks.values.count { |p| p.run_state == :completed }
          failed = @tasks.values.count { |p| p.run_state == :failed }
          total = @tasks.size

          line = if failed > 0
            failed_tasks = @tasks.select { |_, p| p.run_state == :failed }
            first_error = failed_tasks.values.first&.run_error
            error_msg = first_error ? ": #{first_error.message}" : ""
            "#{COLORS[:red]}#{ICONS[:failure]}#{COLORS[:reset]} [#{completed}/#{total}] " \
              "#{failed_tasks.keys.first} failed#{error_msg}"
          else
            "#{COLORS[:green]}#{ICONS[:success]}#{COLORS[:reset]} [#{completed}/#{total}] " \
              "All tasks completed (#{total_duration}ms)"
          end

          @output.print "\r\e[K#{line}\n"
          @output.flush
        end
      end

      def build_status_line
        running_tasks = @tasks.select { |_, p| p.run_state == :running }
        cleaning_tasks = @tasks.select { |_, p| p.clean_state == :cleaning }
        completed = @tasks.values.count { |p| p.run_state == :completed }
        failed = @tasks.values.count { |p| p.run_state == :failed }
        total = @tasks.size

        spinner = SPINNER_FRAMES[@spinner_index]
        status_icon = if failed > 0
          "#{COLORS[:red]}#{ICONS[:failure]}#{COLORS[:reset]}"
        elsif running_tasks.any? || cleaning_tasks.any?
          "#{COLORS[:yellow]}#{spinner}#{COLORS[:reset]}"
        else
          "#{COLORS[:green]}#{ICONS[:success]}#{COLORS[:reset]}"
        end

        # Get current task names
        current_tasks = if cleaning_tasks.any?
          cleaning_tasks.keys.map { |t| short_name(t) }
        else
          running_tasks.keys.map { |t| short_name(t) }
        end

        task_names = current_tasks.first(3).join(", ")
        task_names += "..." if current_tasks.size > 3

        # Get last output message if available
        output_suffix = build_output_suffix(running_tasks.keys.first || cleaning_tasks.keys.first)

        parts = ["#{status_icon} [#{completed}/#{total}]"]
        parts << task_names if task_names && !task_names.empty?
        parts << "|" << output_suffix if output_suffix

        parts.join(" ")
      end

      def build_output_suffix(task_class)
        return nil unless @output_capture && task_class

        last_line = @output_capture.last_line_for(task_class)
        return nil unless last_line && !last_line.strip.empty?

        # Truncate if too long
        max_length = 40
        if last_line.length > max_length
          last_line[0, max_length - 3] + "..."
        else
          last_line
        end
      end

      def short_name(task_class)
        # Remove module prefix for brevity
        task_class.name.split("::").last
      end
    end
  end
end
