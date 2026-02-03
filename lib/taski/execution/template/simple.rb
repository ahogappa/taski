# frozen_string_literal: true

require_relative "default"

module Taski
  module Execution
    module Template
      # Simple template for TTY environments with single-line progress display.
      # Provides spinner animation, colored icons, and status formatting.
      #
      # Output format:
      #   ⠹ [3/5] DeployTask | Uploading files...
      #   ✓ [5/5] All tasks completed (1.2s)
      #
      # @example Usage
      #   layout = Taski::Execution::Layout::Simple.new(
      #     template: Taski::Execution::Template::Simple.new
      #   )
      #
      # @example Custom spinner frames
      #   class MoonTemplate < Taski::Execution::Template::Simple
      #     def spinner_frames
      #       %w[🌑 🌒 🌓 🌔 🌕 🌖 🌗 🌘]
      #     end
      #   end
      #
      # @example Custom status template
      #   class JapaneseTemplate < Taski::Execution::Template::Simple
      #     def format_count(count)
      #       "#{count}件"
      #     end
      #
      #     def status_complete
      #       '{% icon %} {{ done_count | format_count }}完了 ({{ duration | format_duration }})'
      #     end
      #   end
      class Simple < Default
        # Inherits ANSI colors from Base via Default.

        # === Status line templates with spinner/icon ===

        # Template for running status line (with spinner)
        # @return [String] Liquid template string
        def status_running
          "{% spinner %} [{{ done_count | format_count }}/{{ total | format_count }}]{% if task_names %} {{ task_names | truncate_list: 3 }}{% endif %}{% if output_suffix %} | {{ output_suffix | truncate_text: 40 }}{% endif %}"
        end

        # Template for completed status line (with icon)
        # @return [String] Liquid template string
        def status_complete
          "{% icon %} [{{ done_count | format_count }}/{{ total | format_count }}] All tasks completed ({{ duration | format_duration }})"
        end

        # Template for failed status line (with icon)
        # @return [String] Liquid template string
        def status_failed
          "{% icon %} [{{ done_count | format_count }}/{{ total | format_count }}] {{ failed_task_name }} failed{% if error_message %}: {{ error_message }}{% endif %}"
        end
      end
    end
  end
end
