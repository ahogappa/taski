# frozen_string_literal: true

module Taski
  module Progress
    # Terminal control operations with ANSI escape sequences
    class TerminalController
      # ANSI escape sequences
      MOVE_UP = "\033[A"
      CLEAR_LINE = "\033[K"
      MOVE_UP_AND_CLEAR = "#{MOVE_UP}#{CLEAR_LINE}"

      def initialize(output)
        @output = output
      end

      def clear_lines(count)
        return if count == 0

        count.times { @output.print MOVE_UP_AND_CLEAR }
      end

      def puts(text)
        @output.puts text
      end

      def print(text)
        @output.print text
      end

      def flush
        @output.flush
      end
    end
  end
end
