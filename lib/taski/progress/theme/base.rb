# frozen_string_literal: true

module Taski
  module Progress
    module Theme
      # Base class for theme definitions.
      # Theme classes are thin layers that only return Liquid template strings.
      # Rendering (Liquid parsing) is handled by Layout classes.
      #
      # Themes have access to two Drop objects:
      #   task: Task-specific info (name, state, duration, error_message, group_name, stdout)
      #   execution: Execution-level info (state, pending_count, done_count, completed_count,
      #              failed_count, total_count, total_duration, root_task_name, task_names)
      #
      # Use {% if variable %} to conditionally render when a value is present.
      #
      # @example Custom theme
      #   class MyTheme < Taski::Progress::Theme::Base
      #     def task_start
      #       "Starting {{ task.name }}..."
      #     end
      #   end
      #
      #   layout = Taski::Progress::Layout::Log.new(theme: MyTheme.new)
      class Base
        # === Task lifecycle templates ===

        def task_pending
          "[PENDING] {{ task.name | short_name }}"
        end

        def task_start
          "[START] {{ task.name | short_name }}"
        end

        def task_success
          "[DONE] {{ task.name | short_name }}{% if task.duration %} ({{ task.duration | format_duration }}){% endif %}"
        end

        def task_fail
          "[FAIL] {{ task.name | short_name }}{% if task.error_message %}: {{ task.error_message }}{% endif %}"
        end

        def task_skipped
          "[SKIP] {{ task.name | short_name }}"
        end

        # === Clean lifecycle templates ===

        def clean_start
          "[CLEAN] {{ task.name | short_name }}"
        end

        def clean_success
          "[CLEAN DONE] {{ task.name | short_name }}{% if task.duration %} ({{ task.duration | format_duration }}){% endif %}"
        end

        def clean_fail
          "[CLEAN FAIL] {{ task.name | short_name }}{% if task.error_message %}: {{ task.error_message }}{% endif %}"
        end

        # === Group lifecycle templates ===

        def group_start
          '[GROUP] {{ task.name | short_name }}#{{ task.group_name }}'
        end

        def group_success
          '[GROUP DONE] {{ task.name | short_name }}#{{ task.group_name }}{% if task.duration %} ({{ task.duration | format_duration }}){% endif %}'
        end

        def group_fail
          '[GROUP FAIL] {{ task.name | short_name }}#{{ task.group_name }}{% if task.error_message %}: {{ task.error_message }}{% endif %}'
        end

        # === Execution lifecycle templates ===

        def execution_start
          "[TASKI] Starting {{ execution.root_task_name | short_name }}"
        end

        def execution_running
          "[TASKI] Running: {{ execution.done_count }}/{{ execution.total_count }} tasks"
        end

        def execution_complete
          "[TASKI] Completed: {{ execution.completed_count }}/{{ execution.total_count }} tasks ({{ execution.total_duration | format_duration }})"
        end

        def execution_fail
          "[TASKI] Failed: {{ execution.failed_count }}/{{ execution.total_count }} tasks ({{ execution.total_duration | format_duration }})"
        end

        # === Spinner configuration ===

        # Spinner animation frames
        # @return [Array<String>] Array of spinner frame characters
        def spinner_frames
          %w[⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏]
        end

        # Spinner frame update interval in seconds
        # @return [Float] Interval between spinner frame updates
        def spinner_interval
          0.08
        end

        # Screen render interval in seconds
        # @return [Float] Interval between screen updates
        def render_interval
          0.1
        end

        # === Icon configuration ===

        # Icon for successful completion
        # @return [String] Success icon
        def icon_success
          "✓"
        end

        # Icon for failure
        # @return [String] Failure icon
        def icon_failure
          "✗"
        end

        # Icon for pending state
        # @return [String] Pending icon
        def icon_pending
          "○"
        end

        # Icon for skipped state (unselected Section candidate)
        # @return [String] Skipped icon
        def icon_skipped
          "⊘"
        end

        # === Color configuration (ANSI codes) ===

        # Green color ANSI escape code
        # @return [String] ANSI code for green
        def color_green
          "\e[32m"
        end

        # Red color ANSI escape code
        # @return [String] ANSI code for red
        def color_red
          "\e[31m"
        end

        # Yellow color ANSI escape code
        # @return [String] ANSI code for yellow
        def color_yellow
          "\e[33m"
        end

        # Dim color ANSI escape code
        # @return [String] ANSI code for dim
        def color_dim
          "\e[2m"
        end

        # Reset color ANSI escape code
        # @return [String] ANSI code to reset color
        def color_reset
          "\e[0m"
        end

        # === Formatting methods (used by filters) ===

        # Format a count value for display.
        # Override in subclasses to customize count formatting.
        #
        # @param count [Integer] The count value
        # @return [String] Formatted count
        # @example
        #   def format_count(count)
        #     "#{count}件"
        #   end
        def format_count(count)
          count.to_s
        end

        # Format a duration value for display.
        # Override in subclasses to customize duration formatting.
        #
        # @param ms [Integer, Float] Duration in milliseconds
        # @return [String] Formatted duration
        # @example
        #   def format_duration(ms)
        #     "#{ms}ミリ秒"
        #   end
        def format_duration(ms)
          if ms >= 1000
            "#{(ms / 1000.0).round(1)}s"
          else
            "#{ms}ms"
          end
        end

        # Separator for truncate_list filter.
        # @return [String] Separator between list items
        def truncate_list_separator
          ", "
        end

        # Suffix for truncate_list filter when list is truncated.
        # @return [String] Suffix to append when items are omitted
        def truncate_list_suffix
          "..."
        end

        # Suffix for truncate_text filter when text is truncated.
        # @return [String] Suffix to append when text is truncated
        def truncate_text_suffix
          "..."
        end
      end
    end
  end
end
