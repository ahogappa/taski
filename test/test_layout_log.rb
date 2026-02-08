# frozen_string_literal: true

require "test_helper"
require "stringio"
require "taski/progress/layout/log"

class TestLayoutLog < Minitest::Test
  def setup
    @output = StringIO.new
    @layout = Taski::Progress::Layout::Log.new(output: @output)
  end

  # === Task lifecycle output ===

  def test_outputs_task_start
    task_class = stub_task_class("MyTask")
    @layout.on_start
    @layout.on_task_updated(task_class, previous_state: nil, current_state: :pending, phase: :run, timestamp: Time.now)
    @layout.on_task_updated(task_class, previous_state: :pending, current_state: :running, phase: :run, timestamp: Time.now)

    assert_includes @output.string, "[START] MyTask"
  end

  def test_outputs_task_success_with_duration
    task_class = stub_task_class("MyTask")
    started = Time.now
    completed = started + 0.1234

    @layout.on_start
    @layout.on_task_updated(task_class, previous_state: nil, current_state: :pending, phase: :run, timestamp: started)
    @layout.on_task_updated(task_class, previous_state: :pending, current_state: :running, phase: :run, timestamp: started)
    @layout.on_task_updated(task_class, previous_state: :running, current_state: :completed, phase: :run, timestamp: completed)

    assert_includes @output.string, "[DONE] MyTask (123.4ms)"
  end

  def test_outputs_task_success_without_started_at
    task_class = stub_task_class("MyTask")
    @layout.on_start
    # Skip :running (no started_at), go directly to :completed
    @layout.on_task_updated(task_class, previous_state: nil, current_state: :pending, phase: :run, timestamp: Time.now)
    @layout.on_task_updated(task_class, previous_state: :pending, current_state: :completed, phase: :run, timestamp: Time.now)

    assert_includes @output.string, "[DONE] MyTask"
    refute_includes @output.string, "()"
  end

  def test_outputs_task_fail
    task_class = stub_task_class("MyTask")
    now = Time.now
    @layout.on_start
    @layout.on_task_updated(task_class, previous_state: nil, current_state: :pending, phase: :run, timestamp: now)
    @layout.on_task_updated(task_class, previous_state: :pending, current_state: :running, phase: :run, timestamp: now)
    @layout.on_task_updated(task_class, previous_state: :running, current_state: :failed, phase: :run, timestamp: now + 1)

    assert_includes @output.string, "[FAIL] MyTask"
  end

  # === Clean lifecycle output ===

  def test_outputs_clean_start
    task_class = stub_task_class("MyTask")
    now = Time.now
    @layout.on_start
    @layout.on_task_updated(task_class, previous_state: nil, current_state: :pending, phase: :run, timestamp: now)
    @layout.on_task_updated(task_class, previous_state: :pending, current_state: :completed, phase: :run, timestamp: now + 0.1)
    @layout.on_task_updated(task_class, previous_state: :pending, current_state: :running, phase: :clean, timestamp: now + 0.2)

    assert_includes @output.string, "[CLEAN] MyTask"
  end

  def test_outputs_clean_success_with_duration
    task_class = stub_task_class("MyTask")
    now = Time.now
    @layout.on_start
    @layout.on_task_updated(task_class, previous_state: nil, current_state: :pending, phase: :run, timestamp: now)
    @layout.on_task_updated(task_class, previous_state: :pending, current_state: :completed, phase: :run, timestamp: now + 0.1)
    @layout.on_task_updated(task_class, previous_state: :pending, current_state: :running, phase: :clean, timestamp: now + 0.2)
    @layout.on_task_updated(task_class, previous_state: :running, current_state: :completed, phase: :clean, timestamp: now + 0.25)

    assert_includes @output.string, "[CLEAN DONE] MyTask (50.0ms)"
  end

  def test_outputs_clean_fail
    task_class = stub_task_class("MyTask")
    now = Time.now
    @layout.on_start
    @layout.on_task_updated(task_class, previous_state: nil, current_state: :pending, phase: :run, timestamp: now)
    @layout.on_task_updated(task_class, previous_state: :pending, current_state: :completed, phase: :run, timestamp: now + 0.1)
    @layout.on_task_updated(task_class, previous_state: :pending, current_state: :running, phase: :clean, timestamp: now + 0.2)
    @layout.on_task_updated(task_class, previous_state: :running, current_state: :failed, phase: :clean, timestamp: now + 0.3)

    assert_includes @output.string, "[CLEAN FAIL] MyTask"
  end

  # === Group lifecycle output ===

  def test_outputs_group_start
    task_class = stub_task_class("MyTask")
    @layout.on_start
    @layout.on_group_started(task_class, "build", phase: :run, timestamp: Time.now)

    assert_includes @output.string, "[GROUP] MyTask#build"
  end

  def test_outputs_group_completed
    task_class = stub_task_class("MyTask")
    now = Time.now
    @layout.on_start
    @layout.on_group_started(task_class, "build", phase: :run, timestamp: now)
    @layout.on_group_completed(task_class, "build", phase: :run, timestamp: now + 0.2)

    assert_includes @output.string, "[GROUP DONE] MyTask#build"
  end

  # === Execution lifecycle output ===

  def test_outputs_execution_start
    task_class = stub_task_class("BuildTask")
    @layout.context = mock_execution_context(root_task_class: task_class)
    @layout.on_ready
    @layout.on_start

    assert_includes @output.string, "[TASKI] Starting BuildTask"
  end

  def test_outputs_execution_complete
    task_class = stub_task_class("MyTask")
    now = Time.now
    @layout.on_task_updated(task_class, previous_state: nil, current_state: :pending, phase: :run, timestamp: now)
    @layout.on_start
    @layout.on_task_updated(task_class, previous_state: :pending, current_state: :running, phase: :run, timestamp: now)
    @layout.on_task_updated(task_class, previous_state: :running, current_state: :completed, phase: :run, timestamp: now + 0.1)
    @layout.on_stop

    # Check for completion message
    assert_match(/\[TASKI\] Completed: 1\/1 tasks \(\d+ms\)/, @output.string)
  end

  def test_outputs_execution_fail_when_tasks_failed
    task1 = stub_task_class("Task1")
    task2 = stub_task_class("Task2")
    now = Time.now
    @layout.on_task_updated(task1, previous_state: nil, current_state: :pending, phase: :run, timestamp: now)
    @layout.on_task_updated(task2, previous_state: nil, current_state: :pending, phase: :run, timestamp: now)
    @layout.on_start
    @layout.on_task_updated(task1, previous_state: :pending, current_state: :running, phase: :run, timestamp: now)
    @layout.on_task_updated(task1, previous_state: :running, current_state: :completed, phase: :run, timestamp: now + 0.1)
    @layout.on_task_updated(task2, previous_state: :pending, current_state: :running, phase: :run, timestamp: now)
    @layout.on_task_updated(task2, previous_state: :running, current_state: :failed, phase: :run, timestamp: now + 0.1)
    @layout.on_stop

    assert_match(/\[TASKI\] Failed: 1\/2 tasks \(\d+ms\)/, @output.string)
  end

  # === Duration formatting ===

  def test_formats_duration_in_seconds_when_over_1000ms
    task_class = stub_task_class("MyTask")
    started = Time.now
    completed = started + 1.5  # 1500ms

    @layout.on_start
    @layout.on_task_updated(task_class, previous_state: nil, current_state: :pending, phase: :run, timestamp: started)
    @layout.on_task_updated(task_class, previous_state: :pending, current_state: :running, phase: :run, timestamp: started)
    @layout.on_task_updated(task_class, previous_state: :running, current_state: :completed, phase: :run, timestamp: completed)

    assert_includes @output.string, "[DONE] MyTask (1.5s)"
  end

  # === Custom theme ===

  def test_uses_custom_theme
    custom_theme = CustomTestTheme.new
    layout = Taski::Progress::Layout::Log.new(output: @output, theme: custom_theme)

    task_class = stub_task_class("MyTask")
    layout.on_start
    layout.on_task_updated(task_class, previous_state: :pending, current_state: :running, phase: :run, timestamp: Time.now)

    assert_includes @output.string, "CUSTOM START MyTask"
  end

  private

  def stub_task_class(name)
    klass = Class.new
    klass.define_singleton_method(:name) { name }
    klass.define_singleton_method(:cached_dependencies) { [] }
    klass
  end

  def mock_execution_context(root_task_class:, output_capture: nil)
    ctx = Object.new
    ctx.define_singleton_method(:root_task_class) { root_task_class }
    ctx.define_singleton_method(:output_capture) { output_capture }
    ctx
  end

  class CustomTestTheme < Taski::Progress::Theme::Base
    def task_start
      "CUSTOM START {{ task.name }}"
    end
  end
end
