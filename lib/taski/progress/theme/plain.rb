# frozen_string_literal: true

require_relative "default"

module Taski
  module Progress
    module Theme
      # Plain theme for non-TTY environments (CI, log files, piped output).
      # Outputs plain text without terminal escape codes or colors.
      #
      # @example Usage
      #   layout = Taski::Progress::Layout::Log.new(
      #     theme: Taski::Progress::Theme::Plain.new
      #   )
      class Plain < Default
        # === Color configuration (disabled for plain output) ===

        def color_green
          ""
        end

        def color_red
          ""
        end

        def color_yellow
          ""
        end

        def color_dim
          ""
        end

        def color_reset
          ""
        end
      end
    end
  end
end
