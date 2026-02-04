# frozen_string_literal: true

require "test_helper"
require "liquid"
require "taski/progress/theme/base"
require "taski/progress/theme/default"
require "taski/progress/theme/detail"
require "taski/progress/layout/filters"
require "taski/progress/layout/tags"
require "taski/progress/layout/theme_drop"

class TestTheme < Minitest::Test
  def setup
    @theme = Taski::Progress::Theme::Default.new
    @theme_drop = Taski::Progress::Layout::ThemeDrop.new(@theme)
    @environment = Liquid::Environment.build do |env|
      env.register_filter(Taski::Progress::Layout::ColorFilter)
      env.register_tag("spinner", Taski::Progress::Layout::SpinnerTag)
      env.register_tag("icon", Taski::Progress::Layout::IconTag)
    end
  end

  # === Task lifecycle templates ===

  def test_task_start_returns_liquid_template_string
    result = @theme.task_start
    assert_includes result, "{{ task.name | short_name }}"
  end

  def test_task_start_renders_with_task_name
    template_string = @theme.task_start
    rendered = render_template(template_string, "task_name" => "MyTask")
    assert_includes rendered, "MyTask"
    assert_includes rendered, "[START]"
  end

  def test_task_success_returns_liquid_template_string
    result = @theme.task_success
    assert_includes result, "{{ task.name | short_name }}"
  end

  def test_task_success_renders_without_duration
    template_string = @theme.task_success
    rendered = render_template(template_string, "task_name" => "MyTask", "duration" => nil)
    assert_includes rendered, "[DONE] MyTask"
    refute_includes rendered, "()"
  end

  def test_task_success_renders_with_duration
    template_string = @theme.task_success
    rendered = render_template(template_string, "task_name" => "MyTask", "task_duration" => 123)
    assert_includes rendered, "[DONE] MyTask (123ms)"
  end

  def test_task_fail_returns_liquid_template_string
    result = @theme.task_fail
    assert_includes result, "{{ task.name | short_name }}"
  end

  def test_task_fail_renders_without_error
    template_string = @theme.task_fail
    rendered = render_template(template_string, "task_name" => "MyTask", "task_error_message" => nil)
    assert_includes rendered, "[FAIL] MyTask"
    refute_includes rendered, ":"
  end

  def test_task_fail_renders_with_error
    template_string = @theme.task_fail
    rendered = render_template(template_string, "task_name" => "MyTask", "task_error_message" => "Something went wrong")
    assert_includes rendered, "[FAIL] MyTask: Something went wrong"
  end

  # === Clean lifecycle templates ===

  def test_clean_start_returns_liquid_template_string
    result = @theme.clean_start
    assert_includes result, "{{ task.name | short_name }}"
    assert_includes result, "[CLEAN]"
  end

  def test_clean_success_renders_with_duration
    template_string = @theme.clean_success
    rendered = render_template(template_string, "task_name" => "MyTask", "task_duration" => 50)
    assert_includes rendered, "[CLEAN DONE] MyTask (50ms)"
  end

  def test_clean_fail_renders_with_error
    template_string = @theme.clean_fail
    rendered = render_template(template_string, "task_name" => "MyTask", "task_error_message" => "Cleanup failed")
    assert_includes rendered, "[CLEAN FAIL] MyTask: Cleanup failed"
  end

  # === Group lifecycle templates ===

  def test_group_start_returns_liquid_template_string
    result = @theme.group_start
    assert_includes result, "{{ task.name | short_name }}"
    assert_includes result, "{{ task.group_name }}"
  end

  def test_group_start_renders_correctly
    template_string = @theme.group_start
    rendered = render_template(template_string, "task_name" => "MyTask", "group_name" => "build")
    assert_includes rendered, "[GROUP] MyTask#build"
  end

  def test_group_success_renders_with_duration
    template_string = @theme.group_success
    rendered = render_template(template_string,
      "task_name" => "MyTask",
      "group_name" => "build",
      "task_duration" => 200)
    assert_includes rendered, "[GROUP DONE] MyTask#build (200ms)"
  end

  def test_group_fail_renders_with_error
    template_string = @theme.group_fail
    rendered = render_template(template_string,
      "task_name" => "MyTask",
      "group_name" => "build",
      "task_error_message" => "Build failed")
    assert_includes rendered, "[GROUP FAIL] MyTask#build: Build failed"
  end

  # === Execution lifecycle templates ===

  def test_execution_start_returns_liquid_template_string
    result = @theme.execution_start
    assert_includes result, "{{ execution.root_task_name | short_name }}"
    assert_includes result, "[TASKI]"
  end

  def test_execution_start_renders_correctly
    template_string = @theme.execution_start
    rendered = render_template(template_string, "root_task_name" => "BuildTask")
    assert_includes rendered, "[TASKI] Starting BuildTask"
  end

  def test_execution_complete_renders_with_stats
    template_string = @theme.execution_complete
    rendered = render_template(template_string,
      "completed_count" => 5,
      "total_count" => 5,
      "total_duration" => 1234)
    assert_includes rendered, "[TASKI] Completed: 5/5 tasks (1.2s)"
  end

  def test_execution_fail_renders_with_stats
    template_string = @theme.execution_fail
    rendered = render_template(template_string,
      "failed_count" => 2,
      "total_count" => 5,
      "total_duration" => 1234)
    assert_includes rendered, "[TASKI] Failed: 2/5 tasks (1.2s)"
  end

  # === Theme::Base as abstract base class ===

  def test_base_provides_default_implementations
    base = Taski::Progress::Theme::Base.new
    assert_kind_of String, base.task_start
    assert_kind_of String, base.task_success
    assert_kind_of String, base.task_fail
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

  def test_task_pending_returns_liquid_template_string
    result = @theme.task_pending
    assert_includes result, "{{ task.name | short_name }}"
  end

  def test_task_pending_renders_correctly
    template_string = @theme.task_pending
    rendered = render_template(template_string, "task_name" => "MyTask")
    assert_includes rendered, "[PENDING]"
    assert_includes rendered, "MyTask"
  end

  # === Execution running template ===

  def test_execution_running_returns_liquid_template_string
    result = @theme.execution_running
    assert_includes result, "execution.done_count"
    assert_includes result, "execution.total_count"
  end

  def test_execution_running_renders_correctly
    template_string = @theme.execution_running
    rendered = render_template(template_string,
      "done_count" => 3,
      "total_count" => 5)
    assert_includes rendered, "[TASKI] Running: 3/5 tasks"
  end

  private

  def render_template(template_string, variables)
    task_drop = Taski::Progress::Layout::TaskDrop.new(
      name: variables["task_name"],
      state: variables["state"],
      duration: variables["task_duration"],
      error_message: variables["task_error_message"],
      group_name: variables["group_name"],
      stdout: variables["task_stdout"]
    )
    execution_drop = Taski::Progress::Layout::ExecutionDrop.new(
      state: variables["state"],
      pending_count: variables["pending_count"],
      done_count: variables["done_count"],
      completed_count: variables["completed_count"],
      failed_count: variables["failed_count"],
      total_count: variables["total_count"],
      total_duration: variables["total_duration"],
      root_task_name: variables["root_task_name"],
      task_names: variables["task_names"]
    )
    context_vars = {
      "template" => @theme_drop,
      "task" => task_drop,
      "execution" => execution_drop,
      "state" => variables["state"],
      "spinner_index" => variables["spinner_index"]
    }
    Liquid::Template.parse(template_string, environment: @environment).render(context_vars)
  end
end

class TestThemeDetail < Minitest::Test
  def setup
    @theme = Taski::Progress::Theme::Detail.new
    @theme_drop = Taski::Progress::Layout::ThemeDrop.new(@theme)
    @environment = Liquid::Environment.build do |env|
      env.register_filter(Taski::Progress::Layout::ColorFilter)
      env.register_tag("spinner", Taski::Progress::Layout::SpinnerTag)
      env.register_tag("icon", Taski::Progress::Layout::IconTag)
    end
  end

  # === Task pending with icon ===

  def test_task_pending_renders_with_icon
    template_string = @theme.task_pending
    rendered = render_template(template_string, "task_name" => "MyTask", "state" => "pending")
    assert_includes rendered, "○"
    assert_includes rendered, "MyTask"
  end

  # === Task start with spinner ===

  def test_task_start_renders_with_spinner
    template_string = @theme.task_start
    rendered = render_template(template_string, "task_name" => "MyTask", "spinner_index" => 0)
    assert_includes rendered, "⠋"
    assert_includes rendered, "MyTask"
  end

  # === Task success with colored icon ===

  def test_task_success_renders_with_icon
    template_string = @theme.task_success
    rendered = render_template(template_string,
      "task_name" => "MyTask",
      "state" => "completed",
      "task_duration" => 123)
    assert_includes rendered, "✓"
    assert_includes rendered, "MyTask"
    assert_includes rendered, "(123ms)"
  end

  def test_task_success_renders_without_duration
    template_string = @theme.task_success
    rendered = render_template(template_string,
      "task_name" => "MyTask",
      "state" => "completed",
      "task_duration" => nil)
    assert_includes rendered, "✓"
    assert_includes rendered, "MyTask"
    refute_includes rendered, "()"
  end

  # === Task fail with colored icon ===

  def test_task_fail_renders_with_icon
    template_string = @theme.task_fail
    rendered = render_template(template_string,
      "task_name" => "MyTask",
      "state" => "failed",
      "task_error_message" => "Something went wrong")
    assert_includes rendered, "✗"
    assert_includes rendered, "MyTask"
    assert_includes rendered, "Something went wrong"
  end

  def test_task_fail_renders_without_error
    template_string = @theme.task_fail
    rendered = render_template(template_string,
      "task_name" => "MyTask",
      "state" => "failed",
      "task_error_message" => nil)
    assert_includes rendered, "✗"
    assert_includes rendered, "MyTask"
    refute_includes rendered, ":"
  end

  private

  def render_template(template_string, variables)
    task_drop = Taski::Progress::Layout::TaskDrop.new(
      name: variables["task_name"],
      state: variables["state"],
      duration: variables["task_duration"],
      error_message: variables["task_error_message"],
      group_name: variables["group_name"],
      stdout: variables["task_stdout"]
    )
    execution_drop = Taski::Progress::Layout::ExecutionDrop.new(
      state: variables["state"],
      pending_count: variables["pending_count"],
      done_count: variables["done_count"],
      completed_count: variables["completed_count"],
      failed_count: variables["failed_count"],
      total_count: variables["total_count"],
      total_duration: variables["total_duration"],
      root_task_name: variables["root_task_name"],
      task_names: variables["task_names"]
    )
    context_vars = {
      "template" => @theme_drop,
      "task" => task_drop,
      "execution" => execution_drop,
      "state" => variables["state"],
      "spinner_index" => variables["spinner_index"]
    }
    Liquid::Template.parse(template_string, environment: @environment).render(context_vars)
  end
end
