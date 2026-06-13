# frozen_string_literal: true

require "test_helper"
require "taski/progress/theme/base"
require "taski/progress/theme/plain"

# Behavioral tests for the Theme::Base helper API — the plain-Ruby successors
# of the former Liquid filters (short_name, format_duration, truncate_*,
# red/green/yellow/dim) and tags ({% icon %}, {% spinner %}). The fragment
# helpers (*_part) pin the engine-fixed nil/empty semantics that replaced the
# old {% if %} conditionals.
class TestThemeHelpers < Minitest::Test
  def setup
    @theme = Taski::Progress::Theme::Base.new
  end

  # === short_name ===

  def test_short_name_extracts_last_component
    assert_equal "MyTask", @theme.short_name("MyModule::MyTask")
  end

  def test_short_name_returns_input_without_namespace
    assert_equal "MyTask", @theme.short_name("MyTask")
  end

  def test_short_name_nil_returns_empty_string
    assert_equal "", @theme.short_name(nil)
  end

  def test_short_name_coerces_non_string
    assert_equal "MyTask", @theme.short_name(:"MyModule::MyTask")
  end

  # === format_duration ===

  def test_format_duration_milliseconds
    assert_equal "123ms", @theme.format_duration(123)
  end

  def test_format_duration_preserves_float_milliseconds
    assert_equal "123.4ms", @theme.format_duration(123.4)
  end

  def test_format_duration_seconds_at_1000ms
    assert_equal "1.0s", @theme.format_duration(1000)
  end

  def test_format_duration_seconds_rounded_to_one_decimal
    assert_equal "1.2s", @theme.format_duration(1234)
  end

  def test_format_duration_zero
    assert_equal "0ms", @theme.format_duration(0)
  end

  def test_format_duration_nil_returns_empty_string
    # Absorbs the old filter's nil guard so direct calls are safe.
    assert_equal "", @theme.format_duration(nil)
  end

  # === format_count ===

  def test_format_count_default_is_to_s
    assert_equal "5", @theme.format_count(5)
  end

  def test_format_count_custom_override
    theme = Class.new(Taski::Progress::Theme::Base) do
      def format_count(count) = "#{count}件"
    end.new
    assert_equal "5件", theme.format_count(5)
  end

  # === truncate_list ===

  def test_truncate_list_joins_under_limit
    assert_equal "A, B", @theme.truncate_list(%w[A B])
  end

  def test_truncate_list_appends_suffix_over_limit
    assert_equal "A, B, C...", @theme.truncate_list(%w[A B C D])
  end

  def test_truncate_list_exactly_at_limit_has_no_suffix
    assert_equal "A, B, C", @theme.truncate_list(%w[A B C])
  end

  def test_truncate_list_nil_returns_empty_string
    assert_equal "", @theme.truncate_list(nil)
  end

  def test_truncate_list_empty_returns_empty_string
    assert_equal "", @theme.truncate_list([])
  end

  def test_truncate_list_wraps_non_array
    assert_equal "A", @theme.truncate_list("A")
  end

  def test_truncate_list_custom_limit
    assert_equal "A...", @theme.truncate_list(%w[A B], 1)
  end

  def test_truncate_list_honors_separator_and_suffix_knobs
    theme = Class.new(Taski::Progress::Theme::Base) do
      def truncate_list_separator = " / "

      def truncate_list_suffix = "…"
    end.new
    assert_equal "A / B / C…", theme.truncate_list(%w[A B C D])
  end

  # === truncate_text ===

  def test_truncate_text_under_max_unchanged
    assert_equal "short", @theme.truncate_text("short", 10)
  end

  def test_truncate_text_truncates_with_suffix
    assert_equal "Upload...", @theme.truncate_text("Uploading files", 9)
  end

  def test_truncate_text_exactly_at_max_unchanged
    assert_equal "abcdef", @theme.truncate_text("abcdef", 6)
  end

  def test_truncate_text_nil_returns_empty_string
    assert_equal "", @theme.truncate_text(nil, 10)
  end

  def test_truncate_text_zero_max_returns_empty_string
    assert_equal "", @theme.truncate_text("abc", 0)
  end

  def test_truncate_text_negative_max_returns_empty_string
    # Pins the max_length <= 0 guard itself: at exactly 0 the keep.zero? clip
    # path coincidentally also yields "", so only a negative value
    # distinguishes the guard (without it, "..."[0, -1] returns nil).
    assert_equal "", @theme.truncate_text("abc", -1)
  end

  def test_truncate_text_suffix_longer_than_max_clips_suffix
    # Boundary quirk preserved from the old filter: when max_length leaves no
    # room for content, the suffix itself is clipped to max_length.
    assert_equal "..", @theme.truncate_text("abcdef", 2)
  end

  def test_truncate_text_default_max_is_40
    long = "x" * 50
    assert_equal ("x" * 37) + "...", @theme.truncate_text(long)
  end

  # === colorize and shorthands ===

  def test_colorize_wraps_in_color_and_reset
    assert_equal "\e[32mOK\e[0m", @theme.colorize("OK", :green)
  end

  def test_red_green_yellow_dim_shorthands
    assert_equal "\e[31mX\e[0m", @theme.red("X")
    assert_equal "\e[32mX\e[0m", @theme.green("X")
    assert_equal "\e[33mX\e[0m", @theme.yellow("X")
    assert_equal "\e[2mX\e[0m", @theme.dim("X")
  end

  def test_colorize_unknown_color_raises_argument_error
    assert_raises(ArgumentError) { @theme.colorize("X", :blue) }
  end

  def test_colorize_uses_custom_color_codes
    theme = Class.new(Taski::Progress::Theme::Base) do
      def color_red = "\e[91m"
    end.new
    assert_equal "\e[91merror\e[0m", theme.red("error")
  end

  def test_colorize_is_noop_with_plain_theme
    plain = Taski::Progress::Theme::Plain.new
    assert_equal "OK", plain.green("OK")
  end

  # === icon_for (replaces {% icon %}) ===

  def test_icon_for_completed_is_green_success_icon
    assert_equal "\e[32m✓\e[0m", @theme.icon_for(:completed)
  end

  def test_icon_for_failed_is_red_failure_icon
    assert_equal "\e[31m✗\e[0m", @theme.icon_for(:failed)
  end

  def test_icon_for_running_is_yellow_pending_icon
    # Quirk preserved from IconTag: running shows the PENDING icon in yellow.
    assert_equal "\e[33m○\e[0m", @theme.icon_for(:running)
  end

  def test_icon_for_skipped_is_dim_skip_icon
    assert_equal "\e[2m⊘\e[0m", @theme.icon_for(:skipped)
  end

  def test_icon_for_pending_is_uncolored
    assert_equal "○", @theme.icon_for(:pending)
  end

  def test_icon_for_nil_is_uncolored_pending_icon
    assert_equal "○", @theme.icon_for(nil)
  end

  def test_icon_for_unknown_state_is_uncolored_pending_icon
    assert_equal "○", @theme.icon_for(:warming_up)
  end

  def test_icon_for_accepts_string_states
    assert_equal "\e[32m✓\e[0m", @theme.icon_for("completed")
  end

  def test_icon_for_with_plain_theme_has_no_codes
    plain = Taski::Progress::Theme::Plain.new
    assert_equal "✓", plain.icon_for(:completed)
  end

  def test_icon_for_uses_custom_icons
    theme = Class.new(Taski::Progress::Theme::Plain) do
      def icon_success = "🎉"
    end.new
    assert_equal "🎉", theme.icon_for(:completed)
  end

  # === spinner_frame (replaces {% spinner %}) ===

  def test_spinner_frame_returns_indexed_frame
    assert_equal "⠋", @theme.spinner_frame(0)
    assert_equal "⠸", @theme.spinner_frame(3)
  end

  def test_spinner_frame_wraps_around
    assert_equal "⠋", @theme.spinner_frame(10)
  end

  def test_spinner_frame_nil_index_uses_zero
    assert_equal "⠋", @theme.spinner_frame(nil)
  end

  def test_spinner_frame_empty_frames_returns_empty_string
    theme = Class.new(Taski::Progress::Theme::Base) do
      def spinner_frames = []
    end.new
    assert_equal "", theme.spinner_frame(0)
  end

  def test_spinner_frame_nil_frames_returns_empty_string
    theme = Class.new(Taski::Progress::Theme::Base) do
      def spinner_frames = nil
    end.new
    assert_equal "", theme.spinner_frame(0)
  end

  def test_spinner_frame_custom_frames
    theme = Class.new(Taski::Progress::Theme::Base) do
      def spinner_frames = %w[🌑 🌒]
    end.new
    assert_equal "🌒", theme.spinner_frame(1)
    assert_equal "🌑", theme.spinner_frame(2)
  end

  # === Fragment helpers (engine-fixed nil/empty semantics) ===

  def test_duration_part_present
    assert_equal " (123ms)", @theme.duration_part(123)
  end

  def test_duration_part_nil_returns_empty_string
    assert_equal "", @theme.duration_part(nil)
  end

  def test_duration_part_zero_still_renders
    # Strict parity with Liquid truthiness: 0 is truthy.
    assert_equal " (0ms)", @theme.duration_part(0)
  end

  def test_error_part_present
    assert_equal ": Boom", @theme.error_part("Boom")
  end

  def test_error_part_nil_returns_empty_string
    assert_equal "", @theme.error_part(nil)
  end

  def test_error_part_empty_string_returns_empty_string
    # Intentional delta vs Liquid (""-is-truthy rendered a dangling ": ").
    # The branch is unreachable in shipped event flows.
    assert_equal "", @theme.error_part("")
  end

  def test_stdout_part_present_truncates_to_max
    long = "Uploading files to the server with a very long output line here"
    assert_equal " | Uploading files to the server with a ...", @theme.stdout_part(long)
  end

  def test_stdout_part_nil_and_empty_return_empty_string
    assert_equal "", @theme.stdout_part(nil)
    assert_equal "", @theme.stdout_part("")
  end

  def test_task_names_part_short_names_with_leading_space
    assert_equal " TaskA, TaskB", @theme.task_names_part(["A::TaskA", "B::TaskB"])
  end

  def test_task_names_part_truncates_at_limit
    assert_equal " T1, T2, T3...", @theme.task_names_part(%w[A::T1 B::T2 C::T3 D::T4])
  end

  def test_task_names_part_nil_returns_empty_string
    assert_equal "", @theme.task_names_part(nil)
  end

  def test_task_names_part_empty_returns_empty_string
    # Intentional delta vs Liquid ([] was truthy and rendered a trailing space).
    # Unreachable in shipped flows: call sites pass nil for empty.
    assert_equal "", @theme.task_names_part([])
  end
end
