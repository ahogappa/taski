# frozen_string_literal: true

module Taski
  module Execution
    module ProgressFeatures
      # Provides spinner animation functionality for progress displays.
      # Include this module and call start_spinner/stop_spinner to animate.
      #
      # @example
      #   class MyDisplay
      #     include ProgressFeatures::SpinnerAnimation
      #
      #     def start
      #       start_spinner(frames: %w[- \\ | /], interval: 0.1) { render }
      #     end
      #
      #     def stop
      #       stop_spinner
      #     end
      #   end
      module SpinnerAnimation
        DEFAULT_FRAMES = %w[- \\ | /].freeze
        DEFAULT_INTERVAL = 0.1

        # Start the spinner animation in a background thread.
        # @param frames [Array<String>] Animation frame characters
        # @param interval [Float] Seconds between frame updates
        # @yield Block called on each frame update for rendering
        def start_spinner(frames: DEFAULT_FRAMES, interval: DEFAULT_INTERVAL, &render_block)
          @spinner_frames = frames
          @spinner_interval = interval
          @spinner_index = 0
          @spinner_running = true
          @spinner_render_block = render_block

          @spinner_thread = Thread.new do
            while @spinner_running
              @spinner_index = (@spinner_index + 1) % @spinner_frames.size
              @spinner_render_block&.call
              sleep @spinner_interval
            end
          end
        end

        # Stop the spinner animation and wait for thread to finish.
        def stop_spinner
          @spinner_running = false
          @spinner_thread&.join
          @spinner_thread = nil
        end

        # Get the current spinner frame character.
        # @return [String] Current frame character
        def current_frame
          return @spinner_frames&.first unless @spinner_frames && @spinner_index
          @spinner_frames[@spinner_index % @spinner_frames.size]
        end
      end
    end
  end
end
