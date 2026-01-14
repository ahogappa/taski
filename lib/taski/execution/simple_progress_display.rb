# frozen_string_literal: true

require_relative "base_progress_display"

module Taski
  module Execution
    # SimpleProgressDisplay provides a minimalist single-line progress display
    # that shows task execution status in a compact format:
    #
    #   ⠹ [3/5] DeployTask | Uploading files...
    #
    # This is an alternative to TreeProgressDisplay for users who prefer
    # less verbose output.
    class SimpleProgressDisplay < BaseProgressDisplay
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

      def initialize(output: $stdout)
        super
        @spinner_index = 0
        @renderer_thread = nil
        @running = false
      end

      protected

      # Template method: Called when root task is set
      def on_root_task_set
        build_tree_structure
      end

      # Template method: Called when a section impl is registered
      def on_section_impl_registered(section_class, impl_class)
        # Mark the impl task as selected
        unless @tasks.key?(impl_class)
          @tasks[impl_class] = TaskProgress.new
        end
        @tasks[impl_class].is_impl_candidate = false
      end

      # Template method: Determine if display should activate
      def should_activate?
        tty?
      end

      # Template method: Called when display starts
      def on_start
        @running = true
        @output.print "\e[?25l" # Hide cursor
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
        unless @tasks.key?(task_class)
          @tasks[task_class] = TaskProgress.new
        end

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
    end
  end
end
