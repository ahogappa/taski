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
        @thread = nil
      end

      def start(terminal, task_name, &display_callback)
        return if @running

        @running = true
        @frame = 0

        @thread = Thread.new do
          while @running
            current_char = SPINNER_CHARS[@frame % SPINNER_CHARS.length]
            display_callback&.call(current_char, task_name)

            @frame += 1
            sleep FRAME_DELAY
          end
        rescue
          # Prevent crashes during app shutdown or forced thread termination
          # Progress display is auxiliary - errors shouldn't affect main processing
        end
      end

      def stop
        @running = false
        # 0.2s timeout prevents hanging during rapid task execution
        # UI responsiveness is more important than perfect cleanup
        @thread&.join(0.2)
        @thread = nil
      end

      def running?
        @running
      end
    end
  end
end
