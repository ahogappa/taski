# frozen_string_literal: true

require "test_helper"
require "liquid"
require "taski/execution/template/base"
require "taski/execution/template/default"

class TestTemplate < Minitest::Test
  def setup
    @template = Taski::Execution::Template::Default.new
  end

  # === Task lifecycle templates ===

  def test_task_start_returns_liquid_template_string
    result = @template.task_start
    assert_includes result, "{{ task_name }}"
  end

  def test_task_start_renders_with_task_name
    template_string = @template.task_start
    rendered = render_template(template_string, "task_name" => "MyTask")
    assert_includes rendered, "MyTask"
    assert_includes rendered, "[START]"
  end

  def test_task_success_returns_liquid_template_string
    result = @template.task_success
    assert_includes result, "{{ task_name }}"
  end

  def test_task_success_renders_without_duration
    template_string = @template.task_success
    rendered = render_template(template_string, "task_name" => "MyTask", "duration" => nil)
    assert_includes rendered, "[DONE] MyTask"
    refute_includes rendered, "()"
  end

  def test_task_success_renders_with_duration
    template_string = @template.task_success
    rendered = render_template(template_string, "task_name" => "MyTask", "duration" => "123.4ms")
    assert_includes rendered, "[DONE] MyTask (123.4ms)"
  end

  def test_task_fail_returns_liquid_template_string
    result = @template.task_fail
    assert_includes result, "{{ task_name }}"
  end

  def test_task_fail_renders_without_error
    template_string = @template.task_fail
    rendered = render_template(template_string, "task_name" => "MyTask", "error_message" => nil)
    assert_includes rendered, "[FAIL] MyTask"
    refute_includes rendered, ":"
  end

  def test_task_fail_renders_with_error
    template_string = @template.task_fail
    rendered = render_template(template_string, "task_name" => "MyTask", "error_message" => "Something went wrong")
    assert_includes rendered, "[FAIL] MyTask: Something went wrong"
  end

  # === Clean lifecycle templates ===

  def test_clean_start_returns_liquid_template_string
    result = @template.clean_start
    assert_includes result, "{{ task_name }}"
    assert_includes result, "[CLEAN]"
  end

  def test_clean_success_renders_with_duration
    template_string = @template.clean_success
    rendered = render_template(template_string, "task_name" => "MyTask", "duration" => "50.0ms")
    assert_includes rendered, "[CLEAN DONE] MyTask (50.0ms)"
  end

  def test_clean_fail_renders_with_error
    template_string = @template.clean_fail
    rendered = render_template(template_string, "task_name" => "MyTask", "error_message" => "Cleanup failed")
    assert_includes rendered, "[CLEAN FAIL] MyTask: Cleanup failed"
  end

  # === Group lifecycle templates ===

  def test_group_start_returns_liquid_template_string
    result = @template.group_start
    assert_includes result, "{{ task_name }}"
    assert_includes result, "{{ group_name }}"
  end

  def test_group_start_renders_correctly
    template_string = @template.group_start
    rendered = render_template(template_string, "task_name" => "MyTask", "group_name" => "build")
    assert_includes rendered, "[GROUP] MyTask#build"
  end

  def test_group_success_renders_with_duration
    template_string = @template.group_success
    rendered = render_template(template_string,
      "task_name" => "MyTask",
      "group_name" => "build",
      "duration" => "200.0ms")
    assert_includes rendered, "[GROUP DONE] MyTask#build (200.0ms)"
  end

  def test_group_fail_renders_with_error
    template_string = @template.group_fail
    rendered = render_template(template_string,
      "task_name" => "MyTask",
      "group_name" => "build",
      "error_message" => "Build failed")
    assert_includes rendered, "[GROUP FAIL] MyTask#build: Build failed"
  end

  # === Execution lifecycle templates ===

  def test_execution_start_returns_liquid_template_string
    result = @template.execution_start
    assert_includes result, "{{ root_task_name }}"
    assert_includes result, "[TASKI]"
  end

  def test_execution_start_renders_correctly
    template_string = @template.execution_start
    rendered = render_template(template_string, "root_task_name" => "BuildTask")
    assert_includes rendered, "[TASKI] Starting BuildTask"
  end

  def test_execution_complete_renders_with_stats
    template_string = @template.execution_complete
    rendered = render_template(template_string,
      "completed" => 5,
      "total" => 5,
      "duration" => 1234)
    assert_includes rendered, "[TASKI] Completed: 5/5 tasks (1234ms)"
  end

  def test_execution_fail_renders_with_stats
    template_string = @template.execution_fail
    rendered = render_template(template_string,
      "failed" => 2,
      "total" => 5,
      "duration" => 1234)
    assert_includes rendered, "[TASKI] Failed: 2/5 tasks (1234ms)"
  end

  # === Template::Base as abstract base class ===

  def test_base_provides_default_implementations
    base = Taski::Execution::Template::Base.new
    assert_kind_of String, base.task_start
    assert_kind_of String, base.task_success
    assert_kind_of String, base.task_fail
  end

  private

  def render_template(template_string, variables)
    Liquid::Template.parse(template_string).render(variables)
  end
end
