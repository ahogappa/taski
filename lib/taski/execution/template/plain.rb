# frozen_string_literal: true

require_relative "default"

module Taski
  module Execution
    module Template
      # Plain template for non-TTY environments (CI, log files, piped output).
      # Outputs plain text without terminal escape codes or colors.
      #
      # @example Usage
      #   layout = Taski::Execution::Layout::Plain.new(
      #     template: Taski::Execution::Template::Plain.new
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
