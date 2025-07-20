# frozen_string_literal: true

module Taski
  module Progress
    # Captures stdout and maintains last N lines like tail -f
    class OutputCapture
      MAX_LINES = 10
      DISPLAY_LINES = 5

      def initialize(main_output)
        @main_output = main_output
        @buffer = []
        @capturing = false
      end

      def start
        return if @capturing
        @buffer.clear
        @capturing = true
      end

      def stop
        return unless @capturing
        @capturing = false
      end

      def last_lines
        @buffer.last(DISPLAY_LINES)
      end

      def capturing?
        @capturing
      end

      private

      def add_line_to_buffer(line)
        @buffer << line
        @buffer.shift while @buffer.length > MAX_LINES
      end
    end
  end
end
