# frozen_string_literal: true

module Taski
  module Progress
    module Template
      # Base class for template definitions.
      # Template classes are thin layers that only return Liquid template strings.
      # Rendering (Liquid parsing) is handled by Layout classes.
      #
      # Users can subclass this to create custom templates:
      #
      #   class MyTemplate < Taski::Progress::Template::Base
      #     def task_start
      #       "Starting {{ task_name }}..."
      #     end
      #   end
      #
      #   layout = Taski::Progress::Layout::Plain.new(template: MyTemplate.new)
      class Base
        # === Task lifecycle templates ===

        # Template shown when a task is pending (not yet started)
        # @return [String] Liquid template string
        def task_pending
          "[PENDING] {{ task_name }}"
        end

        # Template shown when a task starts running
        # @return [String] Liquid template string
        def task_start
          "[START] {{ task_name }}"
        end

        # Template shown when a task completes successfully
        # Available variables: task_name, duration (optional, in milliseconds)
        # @return [String] Liquid template string
        def task_success
          "[DONE] {{ task_name }}{% if duration %} ({{ duration | format_duration }}){% endif %}"
        end

        # Template shown when a task fails
        # Available variables: task_name, error_message (optional)
        # @return [String] Liquid template string
        def task_fail
          "[FAIL] {{ task_name }}{% if error_message %}: {{ error_message }}{% endif %}"
        end

        # === Clean lifecycle templates ===

        # Template shown when a task's clean phase starts
        # @return [String] Liquid template string
        def clean_start
          "[CLEAN] {{ task_name }}"
        end

        # Template shown when a task's clean phase completes
        # Available variables: task_name, duration (optional, in milliseconds)
        # @return [String] Liquid template string
        def clean_success
          "[CLEAN DONE] {{ task_name }}{% if duration %} ({{ duration | format_duration }}){% endif %}"
        end

        # Template shown when a task's clean phase fails
        # Available variables: task_name, error_message (optional)
        # @return [String] Liquid template string
        def clean_fail
          "[CLEAN FAIL] {{ task_name }}{% if error_message %}: {{ error_message }}{% endif %}"
        end

        # === Group lifecycle templates ===

        # Template shown when a group starts
        # Available variables: task_name, group_name
        # @return [String] Liquid template string
        def group_start
          '[GROUP] {{ task_name }}#{{ group_name }}'
        end

        # Template shown when a group completes successfully
        # Available variables: task_name, group_name, duration (optional, in milliseconds)
        # @return [String] Liquid template string
        def group_success
          '[GROUP DONE] {{ task_name }}#{{ group_name }}{% if duration %} ({{ duration | format_duration }}){% endif %}'
        end

        # Template shown when a group fails
        # Available variables: task_name, group_name, error_message (optional)
        # @return [String] Liquid template string
        def group_fail
          '[GROUP FAIL] {{ task_name }}#{{ group_name }}{% if error_message %}: {{ error_message }}{% endif %}'
        end

        # === Execution lifecycle templates ===

        # Template shown when execution begins
        # Available variables: root_task_name
        # @return [String] Liquid template string
        def execution_start
          "[TASKI] Starting {{ root_task_name }}"
        end

        # Template shown during execution (running state)
        # Available variables: done_count, total, task_names (optional, array), output_suffix (optional)
        # @return [String] Liquid template string
        def execution_running
          "[{{ done_count }}/{{ total }}]{% if task_names %} {{ task_names | truncate_list: 3 }}{% endif %}{% if output_suffix %} | {{ output_suffix | truncate_text: 40 }}{% endif %}"
        end

        # Template shown when all tasks complete successfully
        # Available variables: completed, total, duration (in milliseconds)
        # @return [String] Liquid template string
        def execution_complete
          "[TASKI] Completed: {{ completed }}/{{ total }} tasks ({{ duration | format_duration }})"
        end

        # Template shown when execution ends with failures
        # Available variables: failed, total, duration (in milliseconds)
        # @return [String] Liquid template string
        def execution_fail
          "[TASKI] Failed: {{ failed }}/{{ total }} tasks ({{ duration | format_duration }})"
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
