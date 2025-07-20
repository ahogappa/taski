# frozen_string_literal: true

module Taski
  module Progress
    # Spinner animation with dots-style characters
    class SpinnerAnimation
      SPINNER_CHARS = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"].freeze
      FRAME_DELAY = 0.1

      def initialize
        @frame = 0
        @running = false
      end

      def start(terminal, task_name, &display_callback)
        return if @running

        @running = true
        @frame = 0

        # Simple non-threaded spinner - just show one frame
        current_char = SPINNER_CHARS[@frame % SPINNER_CHARS.length]
        display_callback&.call(current_char, task_name)
      end

      def stop
        @running = false
      end

      def running?
        @running
      end
    end
  end
end
