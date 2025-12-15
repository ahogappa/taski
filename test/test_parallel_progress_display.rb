# frozen_string_literal: true

require "test_helper"

class TestParallelProgressDisplay < Minitest::Test
  def setup
    @output = StringIO.new
  end

  def test_initialize_progress_display
    display = Taski::Execution::ParallelProgressDisplay.new(output: @output)
    assert_instance_of Taski::Execution::ParallelProgressDisplay, display
  end

  def test_register_task
    display = Taski::Execution::ParallelProgressDisplay.new(output: @output)

    task_class = Class.new(Taski::Task)
    display.register_task(task_class)

    # Task should be tracked
    assert display.task_registered?(task_class)
  end

  def test_update_task_state
    display = Taski::Execution::ParallelProgressDisplay.new(output: @output)

    task_class = Class.new(Taski::Task)
    display.register_task(task_class)
    display.update_task(task_class, state: :running)

    # State should be updated
    assert_equal :running, display.task_state(task_class)
  end

  def test_render_output
    display = Taski::Execution::ParallelProgressDisplay.new(output: @output)

    task_class = Class.new(Taski::Task) do
      def self.name
        "TestTask"
      end
    end

    display.register_task(task_class)
    display.update_task(task_class, state: :running)
    display.render

    output = @output.string
    assert_includes output, "TestTask"
  end

  def test_completed_task_shows_checkmark
    display = Taski::Execution::ParallelProgressDisplay.new(output: @output)

    task_class = Class.new(Taski::Task) do
      def self.name
        "CompletedTask"
      end
    end

    display.register_task(task_class)
    display.update_task(task_class, state: :completed, duration: 123.4)
    display.render

    output = @output.string
    assert_includes output, "✅"
    assert_includes output, "CompletedTask"
    assert_includes output, "123.4ms"
  end

  def test_failed_task_shows_cross_mark
    display = Taski::Execution::ParallelProgressDisplay.new(output: @output)

    task_class = Class.new(Taski::Task) do
      def self.name
        "FailedTask"
      end
    end

    display.register_task(task_class)
    display.update_task(task_class, state: :failed, error: StandardError.new("test error"))
    display.render

    output = @output.string
    assert_includes output, "❌"
    assert_includes output, "FailedTask"
  end

  def test_running_task_shows_spinner
    display = Taski::Execution::ParallelProgressDisplay.new(output: @output)

    task_class = Class.new(Taski::Task) do
      def self.name
        "RunningTask"
      end
    end

    display.register_task(task_class)
    display.update_task(task_class, state: :running)
    display.render

    output = @output.string
    # Should contain spinner character (one of: ⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏)
    assert_match(/[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏]/, output)
    assert_includes output, "RunningTask"
  end

  def test_multiple_tasks_displayed
    display = Taski::Execution::ParallelProgressDisplay.new(output: @output)

    task1 = Class.new(Taski::Task) do
      def self.name
        "Task1"
      end
    end

    task2 = Class.new(Taski::Task) do
      def self.name
        "Task2"
      end
    end

    task3 = Class.new(Taski::Task) do
      def self.name
        "Task3"
      end
    end

    display.register_task(task1)
    display.register_task(task2)
    display.register_task(task3)

    display.update_task(task1, state: :completed, duration: 100)
    display.update_task(task2, state: :running)
    display.update_task(task3, state: :pending)

    display.render

    output = @output.string
    assert_includes output, "Task1"
    assert_includes output, "Task2"
    assert_includes output, "Task3"
  end

  def test_integration_with_parallel_execution
    require_relative "fixtures/parallel_tasks"

    Taski::Task.reset!

    display = Taski::Execution::ParallelProgressDisplay.new(output: @output)

    # Register tasks
    display.register_task(ParallelTaskA)
    display.register_task(ParallelTaskB)
    display.register_task(ParallelTaskC)

    # Execute with progress tracking
    # This simulates the real execution flow
    display.update_task(ParallelTaskA, state: :running)
    display.update_task(ParallelTaskB, state: :running)

    result = ParallelTaskC.task_c_value

    # Verify execution worked
    assert_includes result, "TaskA"
    assert_includes result, "TaskB"
  end

  # Test Taski.reset_progress_display!
  def test_taski_reset_progress_display
    # First, enable progress by setting the environment variable
    original_env = ENV["TASKI_FORCE_PROGRESS"]
    ENV["TASKI_FORCE_PROGRESS"] = "1"

    # Reset any existing progress display
    Taski.reset_progress_display!

    # Access progress_display to create a new one
    display = Taski.progress_display
    assert_instance_of Taski::Execution::ParallelProgressDisplay, display

    # Reset should clear it
    Taski.reset_progress_display!

    # Accessing again should create a new instance
    new_display = Taski.progress_display
    refute_same display, new_display
  ensure
    ENV["TASKI_FORCE_PROGRESS"] = original_env
    Taski.reset_progress_display!
  end

  # Test progress_display returns nil when disabled
  def test_taski_progress_display_returns_nil_when_disabled
    original_env = ENV["TASKI_PROGRESS"]
    original_force = ENV["TASKI_FORCE_PROGRESS"]
    ENV["TASKI_PROGRESS"] = nil
    ENV["TASKI_FORCE_PROGRESS"] = nil

    Taski.reset_progress_display!
    assert_nil Taski.progress_display
  ensure
    ENV["TASKI_PROGRESS"] = original_env
    ENV["TASKI_FORCE_PROGRESS"] = original_force
    Taski.reset_progress_display!
  end
end
