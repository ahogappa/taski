# frozen_string_literal: true

module Taski
  module Execution
    module ProgressFeatures
      # Provides terminal control functionality (cursor, screen buffer, etc.)
      # Include this module to get terminal manipulation methods.
      #
      # @example
      #   class MyDisplay
      #     include ProgressFeatures::TerminalControl
      #
      #     def initialize(output: $stdout)
      #       @output = output
      #     end
      #
      #     def start
      #       hide_cursor
      #       use_alternate_buffer
      #     end
      #
      #     def stop
      #       restore_buffer
      #       show_cursor
      #     end
      #   end
      module TerminalControl
        DEFAULT_TERMINAL_WIDTH = 80
        DEFAULT_TERMINAL_HEIGHT = 24

        # Hide the terminal cursor.
        def hide_cursor
          @output.print "\e[?25l"
        end

        # Show the terminal cursor.
        def show_cursor
          @output.print "\e[?25h"
        end

        # Clear the current line.
        def clear_line
          @output.print "\r\e[K"
        end

        # Move cursor up by the specified number of lines.
        # @param lines [Integer] Number of lines to move up
        def move_cursor_up(lines)
          @output.print "\e[#{lines}A"
        end

        # Move cursor to home position (top-left).
        def move_cursor_home
          @output.print "\e[H"
        end

        # Switch to alternate screen buffer.
        def use_alternate_buffer
          @output.print "\e[?1049h"
        end

        # Restore main screen buffer.
        def restore_buffer
          @output.print "\e[?1049l"
        end

        # Check if output is a TTY.
        # @return [Boolean] true if output is a TTY
        def tty?
          @output.respond_to?(:tty?) && @output.tty?
        end

        # Get terminal width in columns.
        # @return [Integer] Terminal width (default 80 if unknown)
        def terminal_width
          return DEFAULT_TERMINAL_WIDTH unless @output.respond_to?(:winsize)
          _, cols = @output.winsize
          cols || DEFAULT_TERMINAL_WIDTH
        rescue
          DEFAULT_TERMINAL_WIDTH
        end

        # Get terminal height in rows.
        # @return [Integer] Terminal height (default 24 if unknown)
        def terminal_height
          return DEFAULT_TERMINAL_HEIGHT unless @output.respond_to?(:winsize)
          rows, _ = @output.winsize
          rows || DEFAULT_TERMINAL_HEIGHT
        rescue
          DEFAULT_TERMINAL_HEIGHT
        end
      end
    end
  end
end
