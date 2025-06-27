# frozen_string_literal: true

require_relative "test_helper"
require "stringio"

class TestTerminalController < Minitest::Test
  def setup
    @output = StringIO.new
    @terminal = Taski::TerminalController.new(@output)
  end

  def test_clear_lines_with_zero_count
    @terminal.clear_lines(0)
    assert_empty @output.string
  end

  def test_clear_lines_with_positive_count
    @terminal.clear_lines(3)
    expected = "\033[A\033[K\033[A\033[K\033[A\033[K"
    assert_equal expected, @output.string
  end

  def test_puts_and_print
    @terminal.puts "test line"
    @terminal.print "test print"

    assert_includes @output.string, "test line\n"
    assert_includes @output.string, "test print"
  end
end

class TestSpinnerAnimation < Minitest::Test
  def setup
    @output = StringIO.new
    @terminal = Taski::TerminalController.new(@output)
    @spinner = Taski::SpinnerAnimation.new
  end

  def teardown
    @spinner.stop if @spinner.running?
  end

  def test_spinner_initialization
    refute @spinner.running?
  end

  def test_spinner_start_and_stop
    callback_called = false
    callback = proc { |char, name| callback_called = true }

    @spinner.start(@terminal, "TestTask", &callback)
    assert @spinner.running?

    sleep 0.15 # Allow animation to run
    @spinner.stop

    refute @spinner.running?
    assert callback_called
  end

  def test_spinner_characters_cycle
    chars_received = []
    callback = proc { |char, name| chars_received << char }

    @spinner.start(@terminal, "TestTask", &callback)
    sleep 0.5 # Allow multiple frames
    @spinner.stop

    # Should have received multiple different spinner characters
    assert chars_received.length > 2
    assert chars_received.uniq.length > 1
  end
end

class TestOutputCapture < Minitest::Test
  def setup
    @output = StringIO.new
    @capture = Taski::OutputCapture.new(@output)
  end

  def teardown
    @capture.stop if @capture.capturing?
  end

  def test_initialization
    refute @capture.capturing?
    assert_empty @capture.last_lines
  end

  def test_capture_start_and_stop
    @capture.start
    assert @capture.capturing?

    puts "test output line"
    sleep 0.1 # Allow capture

    @capture.stop
    refute @capture.capturing?

    # Should have captured the output
    assert_includes @capture.last_lines, "test output line"
  end

  def test_output_buffer_limit
    @capture.start

    # Output more than MAX_LINES to test buffer limit
    15.times { |i| puts "Line #{i}" }
    sleep 0.1

    @capture.stop

    # Should keep only last DISPLAY_LINES (5)
    lines = @capture.last_lines
    assert_equal 5, lines.length
    assert_includes lines.last, "Line 14"
  end

  def test_skip_logger_lines
    @capture.start

    puts "[2025-06-28 07:00:00.000] Logger line"
    puts "Regular output line"
    sleep 0.1

    @capture.stop

    lines = @capture.last_lines
    refute_includes lines, "[2025-06-28 07:00:00.000] Logger line"
    assert_includes lines, "Regular output line"
  end
end

class TestTaskStatus < Minitest::Test
  def test_successful_task_status
    status = Taski::TaskStatus.new(name: "TestTask", duration: 1.234)

    assert_equal "TestTask", status.name
    assert_equal 1.234, status.duration
    assert_nil status.error
    assert status.success?
    refute status.failure?
    assert_equal "✅", status.icon
    assert_equal 1234.0, status.duration_ms
    assert_equal "(1234.0ms)", status.format_duration
  end

  def test_failed_task_status
    error = StandardError.new("Test error")
    status = Taski::TaskStatus.new(name: "FailTask", duration: 0.5, error: error)

    assert_equal "FailTask", status.name
    assert_equal 0.5, status.duration
    assert_equal error, status.error
    refute status.success?
    assert status.failure?
    assert_equal "❌", status.icon
    assert_equal 500.0, status.duration_ms
    assert_equal "(500.0ms)", status.format_duration
  end

  def test_task_without_duration
    status = Taski::TaskStatus.new(name: "TestTask")

    assert_nil status.duration_ms
    assert_equal "", status.format_duration
  end
end

class TestProgressDisplay < Minitest::Test
  def setup
    @output = StringIO.new
    # Make StringIO behave like a TTY for testing
    def @output.tty?
      true
    end
    @progress = Taski::ProgressDisplay.new(output: @output)
  end

  def teardown
    @progress.clear
  end

  def test_initialization
    assert @progress.enabled?
  end

  def test_disabled_for_non_tty
    non_tty_output = StringIO.new
    def non_tty_output.tty?
      false
    end

    progress = Taski::ProgressDisplay.new(output: non_tty_output)
    refute progress.enabled?
  end

  def test_basic_task_completion
    @progress.start_task("TestTask")
    sleep 0.15 # Allow spinner animation
    @progress.complete_task("TestTask", duration: 0.123)

    output_str = @output.string
    assert_includes output_str, "✅ TestTask"
    assert_includes output_str, "(123.0ms)"
  end

  def test_task_failure
    @progress.start_task("FailTask")
    sleep 0.15
    @progress.fail_task("FailTask", error: StandardError.new("Test error"), duration: 0.5)

    output_str = @output.string
    assert_includes output_str, "❌ FailTask"
    assert_includes output_str, "(500.0ms)"
  end

  def test_multiple_tasks_sequence
    # First task
    @progress.start_task("Task1")
    sleep 0.1
    @progress.complete_task("Task1", duration: 0.1)

    # Second task
    @progress.start_task("Task2")
    sleep 0.1
    @progress.complete_task("Task2", duration: 0.2)

    output_str = @output.string
    assert_includes output_str, "✅ Task1"
    assert_includes output_str, "✅ Task2"
  end

  def test_output_capture_during_task
    @progress.start_task("VerboseTask")

    # Simulate task output
    puts "Line 1"
    puts "Line 2"
    puts "Line 3"
    sleep 0.2 # Allow capture and display

    @progress.complete_task("VerboseTask", duration: 0.3)

    output_str = @output.string
    # Should contain spinner animation with task name
    assert_includes output_str, "VerboseTask"
    # Should contain the captured output lines
    assert_includes output_str, "Line 1"
    assert_includes output_str, "Line 2"
    assert_includes output_str, "Line 3"
  end

  def test_clear_functionality
    @progress.start_task("TestTask")
    sleep 0.1
    @progress.complete_task("TestTask", duration: 0.1)

    # Verify there's output
    refute_empty @output.string

    @progress.clear

    # Clear doesn't affect already written output, but resets internal state
    # We test this by checking no errors occur and new tasks work properly
    @progress.start_task("NewTask")
    @progress.complete_task("NewTask", duration: 0.1)

    output_str = @output.string
    assert_includes output_str, "✅ NewTask"
  end

  def test_spinner_animation_characters
    @progress.start_task("AnimationTest")
    sleep 0.3 # Allow multiple animation frames
    @progress.complete_task("AnimationTest", duration: 0.3)

    output_str = @output.string

    # Should contain at least one spinner character
    spinner_chars = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    assert spinner_chars.any? { |char| output_str.include?(char) }
  end
end

class TestProgressDisplayIntegration < Minitest::Test
  def setup
    @output = StringIO.new
    def @output.tty?
      true
    end

    # Set up Taski to use our test progress display
    @original_progress = Taski.instance_variable_get(:@progress_display)
    Taski.instance_variable_set(:@progress_display, Taski::ProgressDisplay.new(output: @output))
  end

  def teardown
    Taski.instance_variable_set(:@progress_display, @original_progress)
  end

  def test_integration_with_taski_framework
    # Create a test task that produces output
    test_task = Class.new(Taski::Task) do
      exports :result

      def build
        puts "Building test task..."
        puts "Processing data..."
        sleep 0.1
        @result = "completed"
      end
    end
    Object.const_set(:IntegrationTestTask, test_task)

    IntegrationTestTask.build

    output_str = @output.string
    assert_includes output_str, "✅ IntegrationTestTask"
    assert_includes output_str, "Building test task..."
  ensure
    Object.send(:remove_const, :IntegrationTestTask) if defined?(IntegrationTestTask)
  end
end
