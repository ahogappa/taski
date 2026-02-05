# frozen_string_literal: true

require "test_helper"
require "stringio"
require "taski/progress/layout/log"

class TestLayoutLog < Minitest::Test
  include LayoutTestHelper

  def setup
    @output = StringIO.new
    @layout = Taski::Progress::Layout::Log.new(output: @output)
  end

  # === Task lifecycle output ===

  def test_outputs_task_start
    task_class = stub_task_class("MyTask")
    @layout.start
    simulate_task_start(@layout, task_class)

    assert_includes @output.string, "[START] MyTask"
  end

  def test_outputs_task_success_with_duration
    task_class = stub_task_class("MyTask")
    @layout.start
    start_time = Time.now
    simulate_task_start(@layout, task_class, timestamp: start_time)
    simulate_task_complete(@layout, task_class, timestamp: start_time + 0.1234)

    assert_match(/\[DONE\] MyTask \(\d+(\.\d+)?ms\)/, @output.string)
  end

  def test_outputs_task_success_without_duration
    task_class = stub_task_class("MyTask")
    @layout.start
    # When start and complete happen at same time, duration should be ~0ms
    now = Time.now
    simulate_task_start(@layout, task_class, timestamp: now)
    simulate_task_complete(@layout, task_class, timestamp: now)

    assert_includes @output.string, "[DONE] MyTask"
  end

  def test_outputs_task_fail
    # Note: error message is not passed via notification - exceptions propagate to top level (Plan design)
    task_class = stub_task_class("MyTask")
    @layout.start
    simulate_task_start(@layout, task_class)
    simulate_task_fail(@layout, task_class)

    assert_includes @output.string, "[FAIL] MyTask"
    # Error details are NOT shown via notification - they come from top-level exception
    refute_includes @output.string, "[FAIL] MyTask:"
  end

  # === Clean lifecycle output ===

  def test_outputs_clean_start
    task_class = stub_task_class("MyTask")
    @layout.start
    simulate_task_start(@layout, task_class)
    simulate_task_complete(@layout, task_class)

    # Set up mock context for clean phase
    mock_context = Object.new
    mock_context.define_singleton_method(:current_phase) { :clean }
    @layout.facade = mock_context

    simulate_task_start(@layout, task_class)

    assert_includes @output.string, "[CLEAN] MyTask"
  end

  def test_outputs_clean_success_with_duration
    task_class = stub_task_class("MyTask")
    @layout.start
    simulate_task_start(@layout, task_class)
    simulate_task_complete(@layout, task_class)

    # Set up mock context for clean phase
    mock_context = Object.new
    mock_context.define_singleton_method(:current_phase) { :clean }
    @layout.facade = mock_context

    start_time = Time.now
    simulate_task_start(@layout, task_class, timestamp: start_time)
    simulate_task_complete(@layout, task_class, timestamp: start_time + 0.05)

    assert_match(/\[CLEAN DONE\] MyTask \(\d+(\.\d+)?ms\)/, @output.string)
  end

  def test_outputs_clean_fail
    # Note: error message is not passed via notification - exceptions propagate to top level (Plan design)
    task_class = stub_task_class("MyTask")
    @layout.start
    simulate_task_start(@layout, task_class)
    simulate_task_complete(@layout, task_class)

    # Set up mock context for clean phase
    mock_context = Object.new
    mock_context.define_singleton_method(:current_phase) { :clean }
    @layout.facade = mock_context

    simulate_task_start(@layout, task_class)
    simulate_task_fail(@layout, task_class)

    assert_includes @output.string, "[CLEAN FAIL] MyTask"
    # Error details are NOT shown via notification - they come from top-level exception
    refute_includes @output.string, "[CLEAN FAIL] MyTask:"
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
    simulate_task_start(@layout, task_class)
    simulate_task_complete(@layout, task_class)
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
    simulate_task_start(@layout, task1)
    simulate_task_complete(@layout, task1)
    simulate_task_start(@layout, task2)
    simulate_task_fail(@layout, task2)
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
    start_time = Time.now
    simulate_task_start(@layout, task_class, timestamp: start_time)
    simulate_task_complete(@layout, task_class, timestamp: start_time + 1.5) # 1500ms

    assert_includes @output.string, "[DONE] MyTask (1.5s)"
  end

  # === Custom theme ===

  def test_uses_custom_theme
    custom_theme = CustomTestTheme.new
    layout = Taski::Progress::Layout::Log.new(output: @output, theme: custom_theme)

    task_class = stub_task_class("MyTask")
    layout.start
    simulate_task_start(layout, task_class)

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
