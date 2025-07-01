# frozen_string_literal: true

module Taski
  # Color utilities for tree display
  # Provides ANSI color codes for enhanced tree visualization
  class TreeColors
    # ANSI color codes
    COLORS = {
      red: "\e[31m",
      green: "\e[32m",
      yellow: "\e[33m",
      blue: "\e[34m",
      magenta: "\e[35m",
      cyan: "\e[36m",
      gray: "\e[90m",
      reset: "\e[0m",
      bold: "\e[1m"
    }.freeze

    class << self
      # Check if colors should be enabled
      # @return [Boolean] true if colors should be used
      def enabled?
        return @enabled unless @enabled.nil?
        @enabled = tty? && !no_color?
      end

      # Enable or disable colors
      # @param value [Boolean] whether to enable colors
      attr_writer :enabled

      # Colorize text for Section names (blue)
      # @param text [String] text to colorize
      # @return [String] colorized text
      def section(text)
        colorize(text, :blue, bold: true)
      end

      # Colorize text for Task names (green)
      # @param text [String] text to colorize
      # @return [String] colorized text
      def task(text)
        colorize(text, :green)
      end

      # Colorize text for implementation candidates (yellow)
      # @param text [String] text to colorize
      # @return [String] colorized text
      def implementations(text)
        colorize(text, :yellow)
      end

      # Colorize tree connectors (gray)
      # @param text [String] text to colorize
      # @return [String] colorized text
      def connector(text)
        colorize(text, :gray)
      end

      private

      # Apply color to text
      # @param text [String] text to colorize
      # @param color [Symbol] color name
      # @param bold [Boolean] whether to make text bold
      # @return [String] colorized text
      def colorize(text, color, bold: false)
        return text unless enabled?

        result = ""
        result += COLORS[:bold] if bold
        result += COLORS[color]
        result += text
        result += COLORS[:reset]
        result
      end

      # Check if output is a TTY
      # @return [Boolean] true if stdout is a TTY
      def tty?
        $stdout.tty?
      end

      # Check if NO_COLOR environment variable is set
      # @return [Boolean] true if colors should be disabled
      def no_color?
        ENV.key?("NO_COLOR")
      end
    end
  end
end
