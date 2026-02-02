# frozen_string_literal: true

module Taski
  module Execution
    module ProgressFeatures
      # Provides formatting utilities for task names and durations.
      # Include this module to get formatting helper methods.
      #
      # @example
      #   class MyDisplay
      #     include ProgressFeatures::Formatting
      #
      #     def render_task(task_class, duration_ms)
      #       "#{short_name(task_class)} (#{format_duration(duration_ms)})"
      #     end
      #   end
      module Formatting
        # Get the short name of a task class (last segment of module path).
        # @param task_class [Class, nil] The task class
        # @return [String] Short name or "Unknown" if nil
        def short_name(task_class)
          return "Unknown" unless task_class
          task_class.name&.split("::")&.last || task_class.to_s
        end

        # Format duration in milliseconds for display.
        # @param ms [Float] Duration in milliseconds
        # @return [String] Formatted duration (e.g., "123.5ms" or "1.5s")
        def format_duration(ms)
          if ms >= 1000
            "#{(ms / 1000.0).round(1)}s"
          else
            "#{ms.round(1)}ms"
          end
        end

        # Truncate text to a maximum length with ellipsis.
        # @param text [String] Text to truncate
        # @param max_length [Integer] Maximum length including ellipsis
        # @return [String] Truncated text
        def truncate(text, max_length)
          return text if text.length <= max_length
          "#{text[0, max_length - 3]}..."
        end
      end
    end
  end
end
