# frozen_string_literal: true

module Taski
  module Progress
    module Theme
      # Base class for theme definitions.
      #
      # Theme methods receive immutable render data (Taski::Progress::TaskInfo /
      # ExecutionInfo) and return the final display String via plain Ruby
      # interpolation. The helpers below replace the former Liquid filters
      # ({{ x | short_name }}) and tags ({% icon %}, {% spinner %}); the *_part
      # fragment helpers replace the former {% if %} conditionals.
      #
      # Contract:
      # - task-level methods:      def task_success(task:, execution: nil)
      # - execution-level methods: def execution_complete(execution:, task: nil)
      #   The layout always passes BOTH keywords (either may be nil).
      # - Themes must be stateless: one instance is shared across event threads
      #   and the render thread.
      # - A raising or wrongly-signatured override never crashes the display:
      #   the layout rescues StandardError, logs Logging::Events::TEMPLATE_ERROR,
      #   and renders "".
      #
      # @example Custom theme
      #   class MyTheme < Taski::Progress::Theme::Base
      #     def task_start(task:, execution: nil)
      #       "Starting #{short_name(task.name)}..."
      #     end
      #   end
      #
      #   Taski.progress.layout = Taski::Progress::Layout::Log
      #   Taski.progress.theme = MyTheme
      class Base
        # === Task lifecycle ===

        def task_pending(task:, execution: nil) = "[PENDING] #{short_name(task.name)}"

        def task_start(task:, execution: nil) = "[START] #{short_name(task.name)}"

        def task_success(task:, execution: nil)
          "[DONE] #{short_name(task.name)}#{duration_part(task.duration)}"
        end

        def task_fail(task:, execution: nil)
          "[FAIL] #{short_name(task.name)}#{error_part(task.error_message)}"
        end

        def task_skip(task:, execution: nil) = "[SKIP] #{short_name(task.name)}"

        # === Clean lifecycle ===

        def clean_start(task:, execution: nil) = "[CLEAN] #{short_name(task.name)}"

        def clean_success(task:, execution: nil)
          "[CLEAN DONE] #{short_name(task.name)}#{duration_part(task.duration)}"
        end

        def clean_fail(task:, execution: nil)
          "[CLEAN FAIL] #{short_name(task.name)}#{error_part(task.error_message)}"
        end

        # === Group lifecycle ===

        def group_start(task:, execution: nil)
          "[GROUP] #{short_name(task.name)}##{task.group_name}"
        end

        def group_success(task:, execution: nil)
          "[GROUP DONE] #{short_name(task.name)}##{task.group_name}#{duration_part(task.duration)}"
        end

        # NOTE: currently no caller (there is no group-failure observer event);
        # kept so the 15-method template vocabulary stays symmetric.
        def group_fail(task:, execution: nil)
          "[GROUP FAIL] #{short_name(task.name)}##{task.group_name}#{error_part(task.error_message)}"
        end

        # === Execution lifecycle ===

        def execution_start(execution:, task: nil)
          "[TASKI] Starting #{short_name(execution.root_task_name)}"
        end

        def execution_running(execution:, task: nil)
          "[TASKI] Running: #{execution.done_count}/#{execution.total_count} tasks"
        end

        def execution_complete(execution:, task: nil)
          "[TASKI] Completed: #{execution.done_count}/#{execution.total_count} tasks (#{format_duration(execution.total_duration)})"
        end

        def execution_fail(execution:, task: nil)
          "[TASKI] Failed: #{execution.failed_count}/#{execution.total_count} tasks (#{format_duration(execution.total_duration)})"
        end

        # === Spinner configuration ===
        # Frames are consumed by the layout's spinner timer (modulo arithmetic)
        # AND by spinner_frame below. Override to customize the animation.

        # @return [Array<String>] Array of spinner frame characters
        def spinner_frames = %w[⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏]

        # @return [Float] seconds between spinner frame updates
        def spinner_interval = 0.08

        # @return [Float] seconds between screen re-renders
        def render_interval = 0.1

        # === Icon configuration ===

        def icon_success = "✓"

        def icon_failure = "✗"

        def icon_pending = "○"

        def icon_skip = "⊘"

        # === Color configuration (ANSI codes; override all to "" for plain output) ===

        def color_green = "\e[32m"

        def color_red = "\e[31m"

        def color_yellow = "\e[33m"

        def color_dim = "\e[2m"

        def color_reset = "\e[0m"

        # === Formatting hooks (override in subclasses) ===

        # @example def format_count(count) = "#{count}件"
        def format_count(count) = count.to_s

        # @param ms [Integer, Float, nil] milliseconds; nil renders "" (absorbs
        #   the old filter's nil guard so direct calls are safe).
        # @example def format_duration(ms) = ms.nil? ? "" : "#{ms}ミリ秒"
        def format_duration(ms)
          return "" if ms.nil?
          (ms >= 1000) ? "#{(ms / 1000.0).round(1)}s" : "#{ms}ms"
        end

        # === Truncation configuration ===

        # Max items shown by task_names_part (was Liquid's `limit: 3`).
        def truncate_list_limit = 3

        def truncate_list_separator = ", "

        def truncate_list_suffix = "..."

        # Max characters shown by stdout_part (was `truncate_text: 40`).
        def truncate_text_max = 40

        def truncate_text_suffix = "..."

        # === Helpers (replace Liquid filters/tags; public for reuse and tests) ===

        # "MyModule::MyTask" -> "MyTask"; nil -> "".
        def short_name(name)
          return "" if name.nil?
          name.to_s.split("::").last || name.to_s
        end

        # Wrap text in a theme color + reset (was the red/green/yellow/dim filters).
        # Closed enum: an unknown color raises ArgumentError (isolated at render).
        # With Plain's "" codes this is a no-op.
        def colorize(text, color)
          code = case color
          when :green then color_green
          when :red then color_red
          when :yellow then color_yellow
          when :dim then color_dim
          else raise ArgumentError, "unknown color #{color.inspect}"
          end
          "#{code}#{text}#{color_reset}"
        end

        def red(text) = colorize(text, :red)

        def green(text) = colorize(text, :green)

        def yellow(text) = colorize(text, :yellow)

        def dim(text) = colorize(text, :dim)

        # State icon with state-dependent color. Replaces {% icon %} exactly:
        # :completed -> green icon_success, :failed -> red icon_failure,
        # :running -> yellow icon_pending (quirk preserved), :skipped -> dim
        # icon_skip, nil/:pending/unknown -> UNCOLORED icon_pending.
        def icon_for(state)
          case state&.to_sym
          when :completed then colorize(icon_success, :green)
          when :failed then colorize(icon_failure, :red)
          when :running then colorize(icon_pending, :yellow)
          when :skipped then colorize(icon_skip, :dim)
          else icon_pending
          end
        end

        # Current spinner glyph for ExecutionInfo#spinner_index. Replaces
        # {% spinner %}, including the empty-frames guard and nil index.
        def spinner_frame(index)
          frames = spinner_frames
          return "" if frames.nil? || frames.empty?
          frames[(index || 0) % frames.size]
        end

        # Truncate text to max_length, appending truncate_text_suffix
        # (was the truncate_text filter; boundary quirks preserved exactly).
        def truncate_text(text, max_length = truncate_text_max)
          return "" if text.nil? || max_length <= 0
          text = text.to_s
          return text if text.length <= max_length
          suffix = truncate_text_suffix
          keep = [max_length - suffix.length, 0].max
          keep.zero? ? suffix[0, max_length] : text[0, keep] + suffix
        end

        # Join up to limit items, appending truncate_list_suffix when truncated
        # (was the truncate_list filter).
        def truncate_list(items, limit = truncate_list_limit)
          return "" if items.nil?
          items = Array(items)
          return "" if items.empty?
          result = items.first(limit).join(truncate_list_separator)
          result += truncate_list_suffix if items.size > limit
          result
        end

        # === Fragment helpers ===
        # The ONLY conditional logic the old templates contained, reified as
        # presence-guarded fragments. The nil/empty decisions are fixed engine
        # semantics.

        # " (1.2s)" when duration present, "" when nil. duration 0/0.0 still
        # renders (strict parity with Liquid truthiness).
        def duration_part(duration)
          duration.nil? ? "" : " (#{format_duration(duration)})"
        end

        # ": message" when present, "" when nil OR empty (delta vs Liquid's
        # ""-is-truthy — branch unreachable in shipped flows, pinned by tests).
        def error_part(error_message)
          (error_message.nil? || error_message.to_s.empty?) ? "" : ": #{error_message}"
        end

        # " | <stdout truncated to truncate_text_max>" or "".
        def stdout_part(stdout)
          (stdout.nil? || stdout.to_s.empty?) ? "" : " | #{truncate_text(stdout, truncate_text_max)}"
        end

        # " TaskA, TaskB, TaskC..." or "" (was Compact's {% for ... limit: 3 %}
        # loop + forloop.last commas + size>3 ellipsis). Honors the
        # truncate_list_* knobs (the old template hard-coded ", "/"...").
        def task_names_part(task_names)
          return "" if task_names.nil? || task_names.empty?
          " " + truncate_list(task_names.map { |n| short_name(n) }, truncate_list_limit)
        end
      end
    end
  end
end
