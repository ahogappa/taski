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
    @layout.start
    @layout.update_task(task_class, state: :running)

    assert_includes @output.string, "[START] MyTask"
  end

  def test_outputs_task_success_with_duration
    task_class = stub_task_class("MyTask")
    @layout.start
    @layout.update_task(task_class, state: :running)
    @layout.update_task(task_class, state: :completed, duration: 123.4)

    assert_includes @output.string, "[DONE] MyTask (123.4ms)"
  end

  def test_outputs_task_success_without_duration
    task_class = stub_task_class("MyTask")
    @layout.start
    @layout.update_task(task_class, state: :running)
    @layout.update_task(task_class, state: :completed)

    assert_includes @output.string, "[DONE] MyTask"
    refute_includes @output.string, "()"
  end

  def test_outputs_task_fail_with_error
    task_class = stub_task_class("MyTask")
    error = StandardError.new("Something went wrong")
    @layout.start
    @layout.update_task(task_class, state: :running)
    @layout.update_task(task_class, state: :failed, error: error)

    assert_includes @output.string, "[FAIL] MyTask: Something went wrong"
  end

  def test_outputs_task_fail_without_error
    task_class = stub_task_class("MyTask")
    @layout.start
    @layout.update_task(task_class, state: :running)
    @layout.update_task(task_class, state: :failed)

    assert_includes @output.string, "[FAIL] MyTask"
    refute_includes @output.string, "[FAIL] MyTask:"
  end

  # === Clean lifecycle output ===

  def test_outputs_clean_start
    task_class = stub_task_class("MyTask")
    @layout.start
    @layout.update_task(task_class, state: :completed, duration: 100)

    # Set up mock context for clean phase
    mock_context = Object.new
    mock_context.define_singleton_method(:current_phase) { :clean }
    @layout.context = mock_context

    @layout.update_task(task_class, state: :running)

    assert_includes @output.string, "[CLEAN] MyTask"
  end

  def test_outputs_clean_success_with_duration
    task_class = stub_task_class("MyTask")
    @layout.start
    @layout.update_task(task_class, state: :completed, duration: 100)

    # Set up mock context for clean phase
    mock_context = Object.new
    mock_context.define_singleton_method(:current_phase) { :clean }
    @layout.context = mock_context

    @layout.update_task(task_class, state: :running)
    @layout.update_task(task_class, state: :completed, duration: 50)

    assert_includes @output.string, "[CLEAN DONE] MyTask (50ms)"
  end

  def test_outputs_clean_fail_with_error
    task_class = stub_task_class("MyTask")
    error = StandardError.new("Cleanup failed")
    @layout.start
    @layout.update_task(task_class, state: :completed, duration: 100)

    # Set up mock context for clean phase
    mock_context = Object.new
    mock_context.define_singleton_method(:current_phase) { :clean }
    @layout.context = mock_context

    @layout.update_task(task_class, state: :running)
    @layout.update_task(task_class, state: :failed, error: error)

    assert_includes @output.string, "[CLEAN FAIL] MyTask: Cleanup failed"
  end

  # === Group lifecycle output ===

  def test_outputs_group_start
    task_class = stub_task_class("MyTask")
    @layout.start
    @layout.update_group(task_class, "build", state: :running)

    assert_includes @output.string, "[GROUP] MyTask#build"
  end

  def test_outputs_group_success_with_duration
    task_class = stub_task_class("MyTask")
    @layout.start
    @layout.update_group(task_class, "build", state: :running)
    @layout.update_group(task_class, "build", state: :completed, duration: 200)

    assert_includes @output.string, "[GROUP DONE] MyTask#build (200ms)"
  end

  def test_outputs_group_fail_with_error
    task_class = stub_task_class("MyTask")
    error = StandardError.new("Build failed")
    @layout.start
    @layout.update_group(task_class, "build", state: :running)
    @layout.update_group(task_class, "build", state: :failed, error: error)

    assert_includes @output.string, "[GROUP FAIL] MyTask#build: Build failed"
  end

  # === Execution lifecycle output ===

  def test_outputs_execution_start
    task_class = stub_task_class("BuildTask")
    @layout.set_root_task(task_class)
    @layout.start

    assert_includes @output.string, "[TASKI] Starting BuildTask"
  end

  def test_outputs_execution_complete
    task_class = stub_task_class("MyTask")
    @layout.register_task(task_class)
    @layout.start
    @layout.update_task(task_class, state: :running)
    @layout.update_task(task_class, state: :completed, duration: 100)
    @layout.stop

    # Check for completion message
    assert_match(%r{\[TASKI\] Completed: 1/1 tasks \(\d+ms\)}, @output.string)
  end

  def test_outputs_execution_fail_when_tasks_failed
    task1 = stub_task_class("Task1")
    task2 = stub_task_class("Task2")
    @layout.register_task(task1)
    @layout.register_task(task2)
    @layout.start
    @layout.update_task(task1, state: :running)
    @layout.update_task(task1, state: :completed, duration: 100)
    @layout.update_task(task2, state: :running)
    @layout.update_task(task2, state: :failed, error: StandardError.new("oops"))
    @layout.stop

    assert_match(%r{\[TASKI\] Failed: 1/2 tasks \(\d+ms\)}, @output.string)
  end

  # === Section impl registration ===

  def test_register_section_impl_registers_impl_task
    section_class = stub_task_class("MySection")
    impl_class = stub_task_class("MyImpl")
    @layout.register_task(section_class)
    @layout.register_section_impl(section_class, impl_class)

    assert @layout.task_registered?(impl_class)
  end

  # === Duration formatting ===

  def test_formats_duration_in_seconds_when_over_1000ms
    task_class = stub_task_class("MyTask")
    @layout.start
    @layout.update_task(task_class, state: :running)
    @layout.update_task(task_class, state: :completed, duration: 1500)

    assert_includes @output.string, "[DONE] MyTask (1.5s)"
  end

  # === Custom theme ===

  def test_uses_custom_theme
    custom_theme = CustomTestTheme.new
    layout = Taski::Progress::Layout::Log.new(output: @output, theme: custom_theme)

    task_class = stub_task_class("MyTask")
    layout.start
    layout.update_task(task_class, state: :running)

    assert_includes @output.string, "CUSTOM START MyTask"
  end

  private

  def stub_task_class(name)
    klass = Class.new
    klass.define_singleton_method(:name) { name }
    klass.define_singleton_method(:cached_dependencies) { [] }
    klass
  end

  class CustomTestTheme < Taski::Progress::Theme::Base
    def task_start
      "CUSTOM START {{ task.name }}"
    end
  end
end
