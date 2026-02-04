# frozen_string_literal: true

require_relative "default"

module Taski
  module Progress
    module Template
      # Simple template for TTY environments with single-line progress display.
      # Provides spinner animation, colored icons, and status formatting.
      #
      # Output format:
      #   ⠹ [3/5] DeployTask | Uploading files...
      #   ✓ [5/5] All tasks completed (1.2s)
      #
      # @example Usage
      #   layout = Taski::Progress::Layout::Simple.new(
      #     template: Taski::Progress::Template::Simple.new
      #   )
      #
      # @example Custom spinner frames
      #   class MoonTemplate < Taski::Progress::Template::Simple
      #     def spinner_frames
      #       %w[🌑 🌒 🌓 🌔 🌕 🌖 🌗 🌘]
      #     end
      #   end
      #
      # @example Custom status template
      #   class JapaneseTemplate < Taski::Progress::Template::Simple
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
        # Adds spinner and icons for TTY environments.

        # Execution running with spinner
        def execution_running
          "{% spinner %} [{{ done_count }}/{{ total_count }}]{% if task_names %} {{ task_names | truncate_list: 3 }}{% endif %}{% if task_stdout %} | {{ task_stdout | truncate_text: 40 }}{% endif %}"
        end

        # Execution complete with icon
        def execution_complete
          "{% icon %} [TASKI] Completed: {{ completed_count }}/{{ total_count }} tasks ({{ duration | format_duration }})"
        end

        # Execution fail with icon
        def execution_fail
          "{% icon %} [TASKI] Failed: {{ failed_count }}/{{ total_count }} tasks ({{ duration | format_duration }})"
        end
      end
    end
  end
end
