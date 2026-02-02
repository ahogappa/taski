# frozen_string_literal: true

module Taski
  module Execution
    module ProgressFeatures
      # Provides ANSI color support for terminal output.
      # Include this module to get colorization methods.
      #
      # @example
      #   class MyDisplay
      #     include ProgressFeatures::AnsiColors
      #
      #     def render_status(text, status)
      #       colorize(text, status_color(status))
      #     end
      #   end
      module AnsiColors
        COLORS = {
          red: 31,
          green: 32,
          yellow: 33,
          blue: 34,
          magenta: 35,
          cyan: 36,
          white: 37,
          gray: 90,
          dim: 2,
          bold: 1,
          reset: 0
        }.freeze

        STATUS_COLORS = {
          completed: :green,
          failed: :red,
          running: :yellow,
          pending: :gray,
          cleaning: :cyan,
          clean_completed: :green,
          clean_failed: :red
        }.freeze

        # Colorize text with one or more ANSI styles.
        # @param text [String] Text to colorize
        # @param styles [Array<Symbol>] Style names (:red, :bold, :dim, etc.)
        # @return [String] Colorized text with ANSI codes
        def colorize(text, *styles)
          return text if styles.empty?

          codes = styles.map { |s| COLORS[s] }.compact
          return text if codes.empty?

          "\e[#{codes.join(";")}m#{text}\e[0m"
        end

        # Get the appropriate color for a task status.
        # @param status [Symbol] Task status (:completed, :failed, :running, :pending)
        # @return [Symbol] Color name
        def status_color(status)
          STATUS_COLORS[status] || :gray
        end
      end
    end
  end
end
