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
      #   Taski.progress.layout = Taski::Progress::Layout::Simple
      #   Taski.progress.theme = Taski::Progress::Theme::Compact
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
      #     def execution_complete(execution:, task: nil)
      #       "#{icon_for(execution.state)} #{format_count(execution.done_count)}完了 (#{format_duration(execution.total_duration)})"
      #     end
      #   end
      class Compact < Default
        # Inherits ANSI colors from Base via Default.
        # Adds spinner and icons for TTY environments.

        # Execution running with spinner
        def execution_running(execution:, task: nil)
          "#{spinner_frame(execution&.spinner_index)} [#{execution.done_count}/#{execution.total_count}]" \
            "#{task_names_part(execution.task_names)}#{stdout_part(task&.stdout)}"
        end

        # Execution complete with icon
        def execution_complete(execution:, task: nil)
          "#{icon_for(execution.state)} [TASKI] Completed: #{execution.done_count}/#{execution.total_count} tasks (#{format_duration(execution.total_duration)})"
        end

        # Execution fail with icon
        def execution_fail(execution:, task: nil)
          "#{icon_for(execution.state)} [TASKI] Failed: #{execution.failed_count}/#{execution.total_count} tasks (#{format_duration(execution.total_duration)})"
        end
      end
    end
  end
end
