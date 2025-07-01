# frozen_string_literal: true

require_relative "task_status"
require_relative "task_formatter"

module Taski
  module Progress
    # Manages the display state and coordinates display updates
    class DisplayManager
      def initialize(terminal, spinner, output_capture, include_captured_output: false)
        @terminal = terminal
        @spinner = spinner
        @output_capture = output_capture
        @include_captured_output = include_captured_output
        @formatter = TaskFormatter.new
        @completed_tasks = []
        @current_display_lines = 0
      end

      def start_task_display(task_name)
        clear_current_display
        @output_capture.start
        start_spinner_display(task_name)
      end

      def complete_task_display(task_name, duration:)
        status = TaskStatus.new(name: task_name, duration: duration)
        finish_task_display(status)
      end

      def fail_task_display(task_name, error:, duration:)
        status = TaskStatus.new(name: task_name, duration: duration, error: error)
        finish_task_display(status)
      end

      def clear_all_displays
        @spinner.stop
        @output_capture.stop
        clear_current_display

        # Display final summary of all completed tasks
        if @completed_tasks.any?
          @completed_tasks.each do |status|
            @terminal.puts @formatter.format_completed_task(status)
          end
          @terminal.flush
        end

        @completed_tasks.clear
        @current_display_lines = 0
      end

      private

      def start_spinner_display(task_name)
        @spinner.start(@terminal, task_name) do |spinner_char, name|
          display_current_state(spinner_char, name)
        end
      end

      def display_current_state(spinner_char, task_name)
        clear_current_display

        lines_count = 0

        # Show only current task to maintain clean, focused UI
        # Displaying all past completed tasks creates visual clutter and reduces readability
        @terminal.puts @formatter.format_current_task(spinner_char, task_name)
        lines_count += 1

        # Display output lines
        @output_capture.last_lines.each do |line|
          @terminal.puts @formatter.format_output_line(line)
          lines_count += 1
        end

        @current_display_lines = lines_count
        @terminal.flush
      end

      def finish_task_display(status)
        @spinner.stop

        # Capture output before stopping
        captured_output = @output_capture.last_lines
        @output_capture.stop
        clear_current_display

        # Test environments need output for verification, production prefers concise display
        # Conditional inclusion balances debugging needs with user experience
        if @include_captured_output && captured_output.any?
          captured_output.each do |line|
            @terminal.puts line.chomp
          end
        end

        @completed_tasks << status
        display_final_state
      end

      def display_final_state
        # Only display the newly completed task (last one)
        if @completed_tasks.any?
          latest_task = @completed_tasks.last
          @terminal.puts @formatter.format_completed_task(latest_task)
        end
        @terminal.flush
        @current_display_lines = 1  # Only one line for the latest task
      end

      def clear_current_display
        @terminal.clear_lines(@current_display_lines)
        @current_display_lines = 0
      end
    end
  end
end
