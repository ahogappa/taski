# frozen_string_literal: true

require "test_helper"
require "taski/progress/info"
require "taski/progress/theme/base"
require "taski/progress/theme/default"
require "taski/progress/theme/detail"

class TestTheme < Minitest::Test
  def setup
    @theme = Taski::Progress::Theme::Default.new
  end

  # === Task lifecycle templates ===

  def test_task_start_renders_with_task_name
    rendered = @theme.task_start(task: task_info(name: "MyTask"))
    assert_includes rendered, "MyTask"
    assert_includes rendered, "[START]"
  end

  def test_task_start_shortens_namespaced_name
    rendered = @theme.task_start(task: task_info(name: "MyModule::MyTask"))
    assert_equal "[START] MyTask", rendered
  end

  def test_task_success_renders_without_duration
    rendered = @theme.task_success(task: task_info(name: "MyTask", duration: nil))
    assert_equal "[DONE] MyTask", rendered
    refute_includes rendered, "()"
  end

  def test_task_success_renders_with_duration
    rendered = @theme.task_success(task: task_info(name: "MyTask", duration: 123))
    assert_equal "[DONE] MyTask (123ms)", rendered
  end

  def test_task_fail_renders_without_error
    rendered = @theme.task_fail(task: task_info(name: "MyTask", error_message: nil))
    assert_equal "[FAIL] MyTask", rendered
    refute_includes rendered, ":"
  end

  def test_task_fail_renders_with_error
    rendered = @theme.task_fail(task: task_info(name: "MyTask", error_message: "Something went wrong"))
    assert_equal "[FAIL] MyTask: Something went wrong", rendered
  end

  # === Clean lifecycle templates ===

  def test_clean_start_renders_with_prefix
    rendered = @theme.clean_start(task: task_info(name: "MyTask"))
    assert_equal "[CLEAN] MyTask", rendered
  end

  def test_clean_success_renders_with_duration
    rendered = @theme.clean_success(task: task_info(name: "MyTask", duration: 50))
    assert_equal "[CLEAN DONE] MyTask (50ms)", rendered
  end

  def test_clean_fail_renders_with_error
    rendered = @theme.clean_fail(task: task_info(name: "MyTask", error_message: "Cleanup failed"))
    assert_equal "[CLEAN FAIL] MyTask: Cleanup failed", rendered
  end

  # === Group lifecycle templates ===

  def test_group_start_renders_correctly
    rendered = @theme.group_start(task: task_info(name: "MyTask", group_name: "build"))
    assert_equal "[GROUP] MyTask#build", rendered
  end

  def test_group_success_renders_with_duration
    rendered = @theme.group_success(task: task_info(name: "MyTask", group_name: "build", duration: 200))
    assert_equal "[GROUP DONE] MyTask#build (200ms)", rendered
  end

  def test_group_fail_renders_with_error
    rendered = @theme.group_fail(task: task_info(name: "MyTask", group_name: "build", error_message: "Build failed"))
    assert_equal "[GROUP FAIL] MyTask#build: Build failed", rendered
  end

  # === Execution lifecycle templates ===

  def test_execution_start_renders_correctly
    rendered = @theme.execution_start(execution: execution_info(root_task_name: "BuildTask"))
    assert_equal "[TASKI] Starting BuildTask", rendered
  end

  def test_execution_complete_renders_with_stats
    rendered = @theme.execution_complete(
      execution: execution_info(done_count: 5, total_count: 5, total_duration: 1234)
    )
    assert_equal "[TASKI] Completed: 5/5 tasks (1.2s)", rendered
  end

  def test_execution_fail_renders_with_stats
    rendered = @theme.execution_fail(
      execution: execution_info(failed_count: 2, total_count: 5, total_duration: 1234)
    )
    assert_equal "[TASKI] Failed: 2/5 tasks (1.2s)", rendered
  end

  def test_execution_running_renders_correctly
    rendered = @theme.execution_running(execution: execution_info(done_count: 3, total_count: 5))
    assert_equal "[TASKI] Running: 3/5 tasks", rendered
  end

  # === Theme::Base as abstract base class ===

  def test_base_provides_default_implementations
    base = Taski::Progress::Theme::Base.new
    task = task_info(name: "T")
    assert_kind_of String, base.task_start(task: task)
    assert_kind_of String, base.task_success(task: task)
    assert_kind_of String, base.task_fail(task: task)
  end

  def test_template_methods_accept_both_keywords
    # The layout always passes BOTH task: and execution: (either may be nil) —
    # every template method must tolerate the unused keyword.
    rendered = @theme.task_start(task: task_info(name: "MyTask"), execution: execution_info)
    assert_equal "[START] MyTask", rendered

    rendered = @theme.execution_running(execution: execution_info(done_count: 1, total_count: 2), task: task_info)
    assert_equal "[TASKI] Running: 1/2 tasks", rendered
  end

  # === Spinner configuration ===

  def test_spinner_frames_returns_array
    result = @theme.spinner_frames
    assert_kind_of Array, result
  end

  def test_spinner_frames_returns_non_empty_array
    result = @theme.spinner_frames
    refute_empty result
  end

  def test_spinner_frames_contains_braille_characters
    result = @theme.spinner_frames
    assert_equal %w[⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏], result
  end

  def test_render_interval_returns_numeric
    result = @theme.render_interval
    assert_kind_of Numeric, result
  end

  def test_render_interval_default_is_0_1
    result = @theme.render_interval
    assert_in_delta 0.1, result, 0.001
  end

  # === Icon configuration ===

  def test_icon_success_returns_string
    result = @theme.icon_success
    assert_kind_of String, result
  end

  def test_icon_success_default_is_checkmark
    result = @theme.icon_success
    assert_equal "✓", result
  end

  def test_icon_failure_returns_string
    result = @theme.icon_failure
    assert_kind_of String, result
  end

  def test_icon_failure_default_is_x
    result = @theme.icon_failure
    assert_equal "✗", result
  end

  def test_icon_pending_returns_string
    result = @theme.icon_pending
    assert_kind_of String, result
  end

  def test_icon_pending_default_is_circle
    result = @theme.icon_pending
    assert_equal "○", result
  end

  def test_icon_skip_returns_string
    result = @theme.icon_skip
    assert_kind_of String, result
  end

  def test_icon_skip_default
    result = @theme.icon_skip
    assert_equal "⊘", result
  end

  def test_task_skip_renders_correctly
    rendered = @theme.task_skip(task: task_info(name: "SkippedTask"))
    assert_equal "[SKIP] SkippedTask", rendered
  end

  # === Color configuration (ANSI codes) ===

  def test_color_green_returns_ansi_code
    result = @theme.color_green
    assert_equal "\e[32m", result
  end

  def test_color_red_returns_ansi_code
    result = @theme.color_red
    assert_equal "\e[31m", result
  end

  def test_color_yellow_returns_ansi_code
    result = @theme.color_yellow
    assert_equal "\e[33m", result
  end

  def test_color_reset_returns_ansi_code
    result = @theme.color_reset
    assert_equal "\e[0m", result
  end

  # === Task pending template ===

  def test_task_pending_renders_correctly
    rendered = @theme.task_pending(task: task_info(name: "MyTask"))
    assert_equal "[PENDING] MyTask", rendered
  end

  private

  def task_info(**fields)
    Taski::Progress::TaskInfo.new(**fields)
  end

  def execution_info(**fields)
    Taski::Progress::ExecutionInfo.new(**fields)
  end
end

class TestThemeDetail < Minitest::Test
  def setup
    @theme = Taski::Progress::Theme::Detail.new
  end

  # === Task pending with icon ===

  def test_task_pending_renders_with_icon
    rendered = @theme.task_pending(task: task_info(name: "MyTask", state: :pending))
    assert_includes rendered, "○"
    assert_includes rendered, "MyTask"
  end

  # === Task start with spinner ===

  def test_task_start_renders_with_spinner
    rendered = @theme.task_start(
      task: task_info(name: "MyTask", state: :running),
      execution: execution_info(spinner_index: 0)
    )
    assert_includes rendered, "⠋"
    assert_includes rendered, "MyTask"
  end

  def test_task_start_uses_spinner_index_from_execution
    rendered = @theme.task_start(
      task: task_info(name: "MyTask", state: :running),
      execution: execution_info(spinner_index: 3)
    )
    assert_includes rendered, "⠸"
  end

  def test_task_start_tolerates_nil_execution
    rendered = @theme.task_start(task: task_info(name: "MyTask", state: :running))
    assert_includes rendered, "⠋"
    assert_includes rendered, "MyTask"
  end

  # === Task success with colored icon ===

  def test_task_success_renders_with_icon
    rendered = @theme.task_success(task: task_info(name: "MyTask", state: :completed, duration: 123))
    assert_includes rendered, "✓"
    assert_includes rendered, "MyTask"
    assert_includes rendered, "(123ms)"
  end

  def test_task_success_renders_without_duration
    rendered = @theme.task_success(task: task_info(name: "MyTask", state: :completed, duration: nil))
    assert_includes rendered, "✓"
    assert_includes rendered, "MyTask"
    refute_includes rendered, "()"
  end

  # === Task fail with colored icon ===

  def test_task_fail_renders_with_icon
    rendered = @theme.task_fail(
      task: task_info(name: "MyTask", state: :failed, error_message: "Something went wrong")
    )
    assert_includes rendered, "✗"
    assert_includes rendered, "MyTask"
    assert_includes rendered, "Something went wrong"
  end

  def test_task_fail_renders_without_error
    rendered = @theme.task_fail(task: task_info(name: "MyTask", state: :failed, error_message: nil))
    assert_includes rendered, "✗"
    assert_includes rendered, "MyTask"
    refute_includes rendered, ":"
  end

  private

  def task_info(**fields)
    Taski::Progress::TaskInfo.new(**fields)
  end

  def execution_info(**fields)
    Taski::Progress::ExecutionInfo.new(**fields)
  end
end
