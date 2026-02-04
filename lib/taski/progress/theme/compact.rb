# frozen_string_literal: true

require_relative "default"

module Taski
  module Progress
    module Theme
      # Compact theme for TTY environments with single-line progress display.
      # Provides spinner animation, colored icons, and status formatting.
      #
      # Output format:
      #   ⠹ [3/5] DeployTask | Uploading files...
      #   ✓ [5/5] All tasks completed (1.2s)
      #
      # @example Usage
      #   layout = Taski::Progress::Layout::Simple.new(
      #     theme: Taski::Progress::Theme::Compact.new
      #   )
      #
      # @example Custom spinner frames
      #   class MoonTheme < Taski::Progress::Theme::Compact
      #     def spinner_frames
      #       %w[🌑 🌒 🌓 🌔 🌕 🌖 🌗 🌘]
      #     end
      #   end
      #
      # @example Custom status theme
      #   class JapaneseTheme < Taski::Progress::Theme::Compact
      #     def format_count(count)
      #       "#{count}件"
      #     end
      #
      #     def status_complete
      #       '{% icon %} {{ execution.done_count | format_count }}完了 ({{ execution.total_duration | format_duration }})'
      #     end
      #   end
      class Compact < Default
        # Inherits ANSI colors from Base via Default.
        # Adds spinner and icons for TTY environments.

        # Execution running with spinner
        def execution_running
          "{% spinner %} [{{ execution.done_count }}/{{ execution.total_count }}]{% if execution.task_names %} {% for name in execution.task_names limit: 3 %}{{ name | short_name }}{% unless forloop.last %}, {% endunless %}{% endfor %}{% if execution.task_names.size > 3 %}...{% endif %}{% endif %}{% if task.stdout %} | {{ task.stdout | truncate_text: 40 }}{% endif %}"
        end

        # Execution complete with icon
        def execution_complete
          "{% icon %} [TASKI] Completed: {{ execution.completed_count }}/{{ execution.total_count }} tasks ({{ execution.total_duration | format_duration }})"
        end

        # Execution fail with icon
        def execution_fail
          "{% icon %} [TASKI] Failed: {{ execution.failed_count }}/{{ execution.total_count }} tasks ({{ execution.total_duration | format_duration }})"
        end
      end
    end
  end
end
