# frozen_string_literal: true

require "stringio"

module Taski
  module Execution
    # Captures stdout during task execution and forwards latest line to progress display.
    # When tree progress is active, stdout is suppressed (only captured for display next to task).
    class OutputCapture
      def initialize(task_class, progress_display:, original_stdout: $stdout)
        @task_class = task_class
        @progress_display = progress_display
        @original_stdout = original_stdout
        @buffer = StringIO.new
      end

      # Write to capture buffer only (suppress actual output during tree display)
      def write(str)
        @buffer.write(str)

        # Extract last non-empty line and update progress display
        update_progress_with_latest_line(str)

        str.length
      end

      def puts(*args)
        if args.empty?
          write("\n")
        else
          args.each do |arg|
            line = arg.to_s
            write(line)
            write("\n") unless line.end_with?("\n")
          end
        end
        nil
      end

      def print(*args)
        args.each { |arg| write(arg.to_s) }
        nil
      end

      def flush
        @original_stdout.flush
      end

      def tty?
        @original_stdout.tty?
      end

      # Get all captured output
      def captured_output
        @buffer.string
      end

      private

      def update_progress_with_latest_line(str)
        return unless @progress_display

        # Get the last meaningful line
        lines = str.split("\n")
        last_line = lines.reverse.find { |l| !l.strip.empty? }
        return unless last_line

        @progress_display.update_task_output(@task_class, last_line.strip)
      end
    end
  end
end
