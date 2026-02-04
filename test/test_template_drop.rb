# frozen_string_literal: true

require "minitest/autorun"
require "liquid"
require_relative "../lib/taski/progress/layout/template_drop"
require_relative "../lib/taski/progress/template/base"

class TestTemplateDrop < Minitest::Test
  def setup
    @template = Taski::Progress::Template::Base.new
    @drop = Taski::Progress::Layout::TemplateDrop.new(@template)
  end

  def test_template_drop_inherits_from_liquid_drop
    assert Taski::Progress::Layout::TemplateDrop < Liquid::Drop
  end

  def test_color_red_delegation
    assert_equal @template.color_red, @drop.color_red
    assert_equal "\e[31m", @drop.color_red
  end

  def test_color_green_delegation
    assert_equal @template.color_green, @drop.color_green
    assert_equal "\e[32m", @drop.color_green
  end

  def test_color_yellow_delegation
    assert_equal @template.color_yellow, @drop.color_yellow
    assert_equal "\e[33m", @drop.color_yellow
  end

  def test_color_dim_delegation
    assert_equal @template.color_dim, @drop.color_dim
    assert_equal "\e[2m", @drop.color_dim
  end

  def test_color_reset_delegation
    assert_equal @template.color_reset, @drop.color_reset
    assert_equal "\e[0m", @drop.color_reset
  end

  def test_spinner_frames_delegation
    assert_equal @template.spinner_frames, @drop.spinner_frames
    assert_equal %w[⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏], @drop.spinner_frames
  end

  def test_render_interval_delegation
    assert_equal @template.render_interval, @drop.render_interval
    assert_equal 0.1, @drop.render_interval
  end

  def test_icon_success_delegation
    assert_equal @template.icon_success, @drop.icon_success
    assert_equal "✓", @drop.icon_success
  end

  def test_icon_failure_delegation
    assert_equal @template.icon_failure, @drop.icon_failure
    assert_equal "✗", @drop.icon_failure
  end

  def test_icon_pending_delegation
    assert_equal @template.icon_pending, @drop.icon_pending
    assert_equal "○", @drop.icon_pending
  end

  def test_drop_works_with_custom_template
    custom_template = Class.new(Taski::Progress::Template::Base) do
      def color_red
        "\e[91m"  # bright red
      end

      def spinner_frames
        %w[| / - \\]
      end

      def icon_success
        "[OK]"
      end
    end.new

    custom_drop = Taski::Progress::Layout::TemplateDrop.new(custom_template)

    assert_equal "\e[91m", custom_drop.color_red
    assert_equal %w[| / - \\], custom_drop.spinner_frames
    assert_equal "[OK]", custom_drop.icon_success
    # Non-overridden methods should still work
    assert_equal "\e[32m", custom_drop.color_green
    assert_equal "✗", custom_drop.icon_failure
  end

  def test_drop_can_be_used_in_liquid_context
    environment = Liquid::Environment.build
    liquid_template = Liquid::Template.parse(
      "Color: {{ template.color_red }}",
      environment: environment
    )
    result = liquid_template.render("template" => @drop)

    assert_equal "Color: \e[31m", result
  end

  def test_drop_exposes_spinner_frames_as_array
    environment = Liquid::Environment.build
    liquid_template = Liquid::Template.parse(
      "{% for frame in template.spinner_frames %}{{ frame }}{% endfor %}",
      environment: environment
    )
    result = liquid_template.render("template" => @drop)

    assert_equal "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏", result
  end

  def test_format_count_delegation
    assert_equal @template.format_count(5), @drop.format_count(5)
    assert_equal "5", @drop.format_count(5)
  end

  def test_format_duration_delegation
    assert_equal @template.format_duration(500), @drop.format_duration(500)
    assert_equal "500ms", @drop.format_duration(500)
    assert_equal "1.5s", @drop.format_duration(1500)
  end

  def test_format_methods_with_custom_template
    custom_template = Class.new(Taski::Progress::Template::Base) do
      def format_count(count)
        "#{count}件"
      end

      def format_duration(ms)
        "#{ms}ミリ秒"
      end
    end.new

    custom_drop = Taski::Progress::Layout::TemplateDrop.new(custom_template)

    assert_equal "3件", custom_drop.format_count(3)
    assert_equal "100ミリ秒", custom_drop.format_duration(100)
  end
end

# TaskDrop: Drop for task-specific variables
class TestTaskDrop < Minitest::Test
  def test_task_drop_inherits_from_liquid_drop
    assert Taski::Progress::Layout::TaskDrop < Liquid::Drop
  end

  def test_exposes_task_name
    drop = Taski::Progress::Layout::TaskDrop.new(name: "MyTask")
    assert_equal "MyTask", drop.name
  end

  def test_exposes_state
    drop = Taski::Progress::Layout::TaskDrop.new(state: :running)
    assert_equal :running, drop.state
  end

  def test_exposes_duration
    drop = Taski::Progress::Layout::TaskDrop.new(duration: 123)
    assert_equal 123, drop.duration
  end

  def test_exposes_error_message
    drop = Taski::Progress::Layout::TaskDrop.new(error_message: "Something failed")
    assert_equal "Something failed", drop.error_message
  end

  def test_exposes_group_name
    drop = Taski::Progress::Layout::TaskDrop.new(group_name: "build")
    assert_equal "build", drop.group_name
  end

  def test_exposes_stdout
    drop = Taski::Progress::Layout::TaskDrop.new(stdout: "output text")
    assert_equal "output text", drop.stdout
  end

  def test_nil_values_for_unset_attributes
    drop = Taski::Progress::Layout::TaskDrop.new
    assert_nil drop.name
    assert_nil drop.state
    assert_nil drop.duration
    assert_nil drop.error_message
    assert_nil drop.group_name
    assert_nil drop.stdout
  end

  def test_can_be_used_in_liquid_template
    drop = Taski::Progress::Layout::TaskDrop.new(name: "BuildTask", state: :completed, duration: 500)
    liquid_template = Liquid::Template.parse("{{ task.name }} ({{ task.state }})")
    result = liquid_template.render("task" => drop)

    assert_equal "BuildTask (completed)", result
  end
end

# ExecutionDrop: Drop for execution-level variables
class TestExecutionDrop < Minitest::Test
  def test_execution_drop_inherits_from_liquid_drop
    assert Taski::Progress::Layout::ExecutionDrop < Liquid::Drop
  end

  def test_exposes_state
    drop = Taski::Progress::Layout::ExecutionDrop.new(state: :completed)
    assert_equal :completed, drop.state
  end

  def test_exposes_pending_count
    drop = Taski::Progress::Layout::ExecutionDrop.new(pending_count: 3)
    assert_equal 3, drop.pending_count
  end

  def test_exposes_done_count
    drop = Taski::Progress::Layout::ExecutionDrop.new(done_count: 5)
    assert_equal 5, drop.done_count
  end

  def test_exposes_completed_count
    drop = Taski::Progress::Layout::ExecutionDrop.new(completed_count: 4)
    assert_equal 4, drop.completed_count
  end

  def test_exposes_failed_count
    drop = Taski::Progress::Layout::ExecutionDrop.new(failed_count: 1)
    assert_equal 1, drop.failed_count
  end

  def test_exposes_total_count
    drop = Taski::Progress::Layout::ExecutionDrop.new(total_count: 10)
    assert_equal 10, drop.total_count
  end

  def test_exposes_total_duration
    drop = Taski::Progress::Layout::ExecutionDrop.new(total_duration: 1500)
    assert_equal 1500, drop.total_duration
  end

  def test_exposes_root_task_name
    drop = Taski::Progress::Layout::ExecutionDrop.new(root_task_name: "MainTask")
    assert_equal "MainTask", drop.root_task_name
  end

  def test_exposes_task_names
    drop = Taski::Progress::Layout::ExecutionDrop.new(task_names: ["TaskA", "TaskB"])
    assert_equal ["TaskA", "TaskB"], drop.task_names
  end

  def test_nil_values_for_unset_attributes
    drop = Taski::Progress::Layout::ExecutionDrop.new
    assert_nil drop.state
    assert_nil drop.pending_count
    assert_nil drop.done_count
    assert_nil drop.completed_count
    assert_nil drop.failed_count
    assert_nil drop.total_count
    assert_nil drop.total_duration
    assert_nil drop.root_task_name
    assert_nil drop.task_names
  end

  def test_can_be_used_in_liquid_template
    drop = Taski::Progress::Layout::ExecutionDrop.new(
      completed_count: 5,
      total_count: 10,
      total_duration: 2000
    )
    liquid_template = Liquid::Template.parse("[{{ execution.completed_count }}/{{ execution.total_count }}]")
    result = liquid_template.render("execution" => drop)

    assert_equal "[5/10]", result
  end
end
