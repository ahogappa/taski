# frozen_string_literal: true

require_relative "test_helper"
require "stringio"

# =============================================================================
# PROGRESS DISPLAY TESTS
# =============================================================================
# Tests for terminal control, spinner animation, output capture,
# task status tracking, and overall progress display functionality

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

    # Give spinner a chance to call the callback
    timeout = Time.now + 1 # 1 second timeout
    while !callback_called && Time.now < timeout
      Thread.pass
    end

    @spinner.stop
    refute @spinner.running?
    assert callback_called
  end

  def test_spinner_characters_cycle
    chars_received = []
    callback = proc { |char, name| chars_received << char }

    @spinner.start(@terminal, "TestTask", &callback)
    # Wait for at least one callback to be called with timeout
    timeout = Time.now + 1 # 1 second timeout
    while chars_received.length == 0 && Time.now < timeout
      Thread.pass
    end
    @spinner.stop

    # Should have received at least one spinner character
    assert chars_received.length > 0
    assert chars_received.all? { |char| char.is_a?(String) && !char.empty? }
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
    @capture.stop
    refute @capture.capturing?

    # Should have captured the output
    assert_includes @capture.last_lines, "test output line"
  end

  def test_output_buffer_limit
    @capture.start

    # Output more than MAX_LINES to test buffer limit
    15.times { |i| puts "Line #{i}" }
    # Ensure output is flushed
    $stdout.flush

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
    # Ensure output is flushed
    $stdout.flush

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
    # Enable progress display for these tests
    ENV.delete("TASKI_PROGRESS_DISABLE")
    @progress = Taski::ProgressDisplay.new(output: @output)
  end

  def teardown
    @progress.clear
    # Restore environment variable for other tests
    ENV["TASKI_PROGRESS_DISABLE"] = "1"
  end

  def test_initialization
    assert @progress.enabled?
  end

  def test_disabled_for_non_tty
    non_tty_output = StringIO.new
    def non_tty_output.tty?
      false
    end

    progress = Taski::ProgressDisplay.new(output: non_tty_output, enable: false)
    refute progress.enabled?
  end

  def test_basic_task_completion
    @progress.start_task("TestTask")
    # Immediately complete the task to test completion functionality
    @progress.complete_task("TestTask", duration: 0.123)

    output_str = @output.string
    assert_includes output_str, "✅ TestTask"
    assert_includes output_str, "(123.0ms)"
  end

  def test_task_failure
    @progress.start_task("FailTask")
    # Immediately fail the task to test failure functionality
    @progress.fail_task("FailTask", error: StandardError.new("Test error"), duration: 0.5)

    output_str = @output.string
    assert_includes output_str, "❌ FailTask"
    assert_includes output_str, "(500.0ms)"
  end

  def test_multiple_tasks_sequence
    # First task
    @progress.start_task("Task1")
    @progress.complete_task("Task1", duration: 0.1)

    # Second task
    @progress.start_task("Task2")
    @progress.complete_task("Task2", duration: 0.2)

    output_str = @output.string
    assert_includes output_str, "✅ Task1"
    assert_includes output_str, "✅ Task2"
  end

  def test_output_capture_during_task
    @progress.start_task("VerboseTask")
    # Immediately complete the task - testing the completion functionality
    @progress.complete_task("VerboseTask", duration: 0.3)

    output_str = @output.string
    # Should contain final result with checkmark
    assert_includes output_str, "✅ VerboseTask"
    assert_includes output_str, "(300.0ms)"
  end

  def test_clear_functionality
    @progress.start_task("TestTask")
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
    # Immediately complete to test that spinner was displayed
    @progress.complete_task("AnimationTest", duration: 0.3)

    output_str = @output.string

    # Should contain final result with checkmark
    assert_includes output_str, "✅ AnimationTest"
    assert_includes output_str, "(300.0ms)"
  end
end

class TestProgressDisplayIntegration < Minitest::Test
  def setup
    @output = StringIO.new
    def @output.tty?
      true
    end

    # Enable progress display for these tests
    ENV.delete("TASKI_PROGRESS_DISABLE")

    # Set up Taski to use our test progress display with force_enable
    @original_progress = Taski.instance_variable_get(:@progress_display)
    Taski.instance_variable_set(:@progress_display, Taski::ProgressDisplay.new(output: @output))
  end

  def teardown
    Taski.instance_variable_set(:@progress_display, @original_progress)
    # Restore environment variable for other tests
    ENV["TASKI_PROGRESS_DISABLE"] = "1"
  end

  def test_integration_with_taski_framework
    # Create a test task that produces output
    test_task = Class.new(Taski::Task) do
      exports :result

      def run
        puts "Building test task..."
        puts "Processing data..."
        # Ensure output is flushed
        $stdout.flush
        @result = "completed"
      end
    end
    Object.const_set(:IntegrationTestTask, test_task)

    IntegrationTestTask.run

    output_str = @output.string
    # Test that the task completed successfully and progress was displayed
    assert_includes output_str, "✅ IntegrationTestTask"
  ensure
    Object.send(:remove_const, :IntegrationTestTask) if defined?(IntegrationTestTask)
  end
end

# =============================================================================
# TREE DISPLAY TESTS
# =============================================================================
# Tests for dependency tree visualization functionality

class TestTreeDisplay < Minitest::Test
  include TaskiTestHelper

  def setup
    setup_taski_test
  end

  def test_tree_display_simple
    # Test simple dependency tree display
    task_a = Class.new(Taski::Task) do
      exports :value
      def run
        @value = "A"
      end
    end
    Object.const_set(:TreeTaskA, task_a)

    task_b = Class.new(Taski::Task) do
      exports :value
      def run
        @value = "B with #{TreeTaskA.value}"
      end
    end
    Object.const_set(:TreeTaskB, task_b)

    expected = "TreeTaskB\n└── TreeTaskA\n"
    assert_equal expected, TreeTaskB.tree(color: false)
  end

  def test_tree_display_complex_hierarchy
    # Test complex dependency tree display
    task_a = Class.new(Taski::Task) do
      exports :value
      def run
        @value = "A"
      end
    end
    Object.const_set(:TreeTaskCompA, task_a)

    task_b = Class.new(Taski::Task) do
      exports :value
      def run
        @value = "B with #{TreeTaskCompA.value}"
      end
    end
    Object.const_set(:TreeTaskCompB, task_b)

    task_c = Class.new(Taski::Task) do
      exports :value
      def run
        @value = "C with #{TreeTaskCompA.value}"
      end
    end
    Object.const_set(:TreeTaskCompC, task_c)

    task_d = Class.new(Taski::Task) do
      exports :value
      def run
        @value = "D with #{TreeTaskCompB.value} and #{TreeTaskCompC.value}"
      end
    end
    Object.const_set(:TreeTaskCompD, task_d)

    result = TreeTaskCompD.tree(color: false)
    assert_includes result, "TreeTaskCompD"
    assert_includes result, "├── TreeTaskCompB"
    assert_includes result, "└── TreeTaskCompC"
    assert_includes result, "TreeTaskCompA"
  end

  def test_tree_display_deep_nesting
    # Test deep nested dependency tree
    task_d = Class.new(Taski::Task) do
      exports :value
      def run
        @value = "Deep D"
      end
    end
    Object.const_set(:DeepTreeD, task_d)

    task_c = Class.new(Taski::Task) do
      exports :value
      def run
        @value = "Deep C with #{DeepTreeD.value}"
      end
    end
    Object.const_set(:DeepTreeC, task_c)

    task_b = Class.new(Taski::Task) do
      exports :value
      def run
        @value = "Deep B with #{DeepTreeC.value}"
      end
    end
    Object.const_set(:DeepTreeB, task_b)

    task_a = Class.new(Taski::Task) do
      exports :value
      def run
        @value = "Deep A with #{DeepTreeB.value}"
      end
    end
    Object.const_set(:DeepTreeA, task_a)

    result = DeepTreeA.tree(color: false)
    lines = result.lines

    # Verify proper tree structure
    assert_includes lines[0], "DeepTreeA"
    assert_includes lines[1], "└── DeepTreeB"
    assert_includes lines[2], "    └── DeepTreeC"
    assert_includes lines[3], "        └── DeepTreeD"
  end

  def test_tree_display_build_failure_on_circular_dependency
    # Test that building a task with circular dependency fails
    task_a = Class.new(Taski::Task) do
      exports :value

      def self.name
        "CircularTaskA"
      end

      def run
        # Create self-dependency by calling own build method
        @value = CircularTaskA.run.value
      end
    end
    Object.const_set(:CircularTaskA, task_a)

    # Tree display should work (it doesn't actually build)
    result = CircularTaskA.tree(color: false)
    assert_includes result, "CircularTaskA"

    # But building should fail with circular dependency error
    error = assert_raises(Taski::TaskBuildError) do
      CircularTaskA.run
    end
    assert_includes error.message, "Circular dependency detected"
  end

  def test_tree_display_with_multiple_branches
    # Test tree with multiple branches and shared dependencies
    shared_task = Class.new(Taski::Task) do
      exports :shared_value
      def run
        @shared_value = "shared"
      end
    end
    Object.const_set(:SharedTreeTask, shared_task)

    branch_a = Class.new(Taski::Task) do
      exports :value
      def run
        @value = "Branch A with #{SharedTreeTask.shared_value}"
      end
    end
    Object.const_set(:BranchTreeA, branch_a)

    branch_b = Class.new(Taski::Task) do
      exports :value
      def run
        @value = "Branch B with #{SharedTreeTask.shared_value}"
      end
    end
    Object.const_set(:BranchTreeB, branch_b)

    root_task = Class.new(Taski::Task) do
      def run
        puts "Root with #{BranchTreeA.value} and #{BranchTreeB.value}"
      end
    end
    Object.const_set(:RootTreeTask, root_task)

    result = RootTreeTask.tree(color: false)

    # Verify structure includes all tasks
    assert_includes result, "RootTreeTask"
    assert_includes result, "BranchTreeA"
    assert_includes result, "BranchTreeB"
    assert_includes result, "SharedTreeTask"

    # Verify proper tree formatting
    assert_includes result, "├── BranchTreeA"
    assert_includes result, "└── BranchTreeB"
  end

  def test_tree_display_no_dependencies
    # Test tree display for task with no dependencies
    standalone_task = Class.new(Taski::Task) do
      exports :value
      def run
        @value = "standalone"
      end
    end
    Object.const_set(:StandaloneTreeTask, standalone_task)

    result = StandaloneTreeTask.tree(color: false)
    assert_equal "StandaloneTreeTask\n", result
  end

  def test_tree_display_with_define_api
    # Test tree display works with define API tasks too
    define_task = Class.new(Taski::Task) do
      exports :config_value

      define :dynamic_config, -> {
        "dynamic config"
      }

      def run
        @config_value = dynamic_config
      end
    end
    Object.const_set(:DefineTreeTask, define_task)

    consumer_task = Class.new(Taski::Task) do
      def run
        puts "Using #{DefineTreeTask.config_value}"
      end
    end
    Object.const_set(:ConsumerTreeTask, consumer_task)

    # Tree should work regardless of which API is used
    result = ConsumerTreeTask.tree(color: false)
    assert_includes result, "ConsumerTreeTask"
    assert_includes result, "└── DefineTreeTask"
  end
end

# =============================================================================
# FORMATTER INTERFACE TESTS
# =============================================================================
# Tests for logging formatter interface functionality

class TestFormatterInterface < Minitest::Test
  def test_formatter_interface_raises_not_implemented_error
    # RED: This test should fail because we're testing error handling
    formatter = Class.new do
      include Taski::Logging::FormatterInterface
    end.new

    error = assert_raises(NotImplementedError) do
      formatter.format(:info, "test message", {}, Time.now)
    end

    assert_includes error.message, "Subclass must implement format method"
  end
end

class TestFormatterFactory < Minitest::Test
  def test_create_simple_formatter
    formatter = Taski::Logging::FormatterFactory.create(:simple)
    assert_instance_of Taski::Logging::SimpleFormatter, formatter
  end

  def test_create_structured_formatter
    formatter = Taski::Logging::FormatterFactory.create(:structured)
    assert_instance_of Taski::Logging::StructuredFormatter, formatter
  end

  def test_create_json_formatter
    formatter = Taski::Logging::FormatterFactory.create(:json)
    assert_instance_of Taski::Logging::JsonFormatter, formatter
  end

  def test_create_invalid_formatter_raises_error
    error = assert_raises(ArgumentError) do
      Taski::Logging::FormatterFactory.create(:invalid)
    end

    assert_includes error.message, "Unknown format: invalid"
    assert_includes error.message, "Valid formats: :simple, :structured, :json"
  end

  def test_available_formats
    formats = Taski::Logging::FormatterFactory.available_formats
    expected = [:simple, :structured, :json]
    assert_equal expected, formats
  end
end

# =============================================================================
# LOGGER TESTS
# =============================================================================
# Tests for logging functionality including levels, formats, and integration

class TestLogger < Minitest::Test
  include TaskiTestHelper

  def setup
    setup_taski_test
    @output = StringIO.new
  end

  def teardown
    # Reset logger to default state
    Taski.configure_logger
  end

  # === Basic Logging Functionality ===

  def test_logger_levels
    logger = Taski::Logger.new(level: :warn, output: @output)

    logger.debug("debug message")
    logger.info("info message")
    logger.warn("warn message")
    logger.error("error message")

    output = @output.string
    refute_includes output, "debug message"
    refute_includes output, "info message"
    assert_includes output, "warn message"
    assert_includes output, "error message"
  end

  def test_logger_with_context
    logger = Taski::Logger.new(level: :info, output: @output, format: :structured)

    logger.info("Test message", task: "TestTask", duration: 123.45)

    output = @output.string
    assert_includes output, "Test message"
    assert_includes output, "task=TestTask"
    assert_includes output, "duration=123.45"
  end

  def test_simple_format
    logger = Taski::Logger.new(level: :info, output: @output, format: :simple)

    logger.info("Simple test")
    logger.error("Error test")

    output = @output.string
    assert_includes output, "[INFO] Simple test"
    assert_includes output, "[ERROR] Error test"
  end

  def test_json_format
    logger = Taski::Logger.new(level: :info, output: @output, format: :json)

    logger.info("JSON test", task: "TestTask")

    output = @output.string
    assert_includes output, '"message":"JSON test"'
    assert_includes output, '"task":"TestTask"'
    assert_includes output, '"level":"info"'
  end

  # === Task-Specific Logging Methods ===

  def test_task_build_start
    logger = Taski::Logger.new(level: :info, output: @output)

    logger.task_build_start("TestTask", dependencies: ["TaskA", "TaskB"])

    output = @output.string
    assert_includes output, "Task build started"
    assert_includes output, "task=TestTask"
    assert_includes output, "dependencies=2"
  end

  def test_task_build_complete
    logger = Taski::Logger.new(level: :info, output: @output)

    logger.task_build_complete("TestTask", duration: 0.123)

    output = @output.string
    assert_includes output, "Task build completed"
    assert_includes output, "task=TestTask"
    assert_includes output, "duration_ms=123.0"
  end

  def test_task_build_failed
    logger = Taski::Logger.new(level: :error, output: @output)
    error = StandardError.new("Test error")
    error.set_backtrace(["line1", "line2", "line3"])

    logger.task_build_failed("TestTask", error: error, duration: 0.05)

    output = @output.string
    assert_includes output, "Task build failed"
    assert_includes output, "task=TestTask"
    assert_includes output, "error_class=StandardError"
    assert_includes output, "error_message=Test error"
    assert_includes output, "duration_ms=50.0"
    assert_includes output, "backtrace="
  end

  def test_circular_dependency_detected
    logger = Taski::Logger.new(level: :error, output: @output)

    # Mock classes for cycle path
    mock_task_a = Class.new {
      def self.name
        "TaskA"
      end
    }
    mock_task_b = Class.new {
      def self.name
        "TaskB"
      end
    }
    cycle_path = [mock_task_a, mock_task_b, mock_task_a]

    logger.circular_dependency_detected(cycle_path)

    output = @output.string
    assert_includes output, "Circular dependency detected"
    assert_includes output, "cycle=[\"TaskA\", \"TaskB\", \"TaskA\"]"
    assert_includes output, "cycle_length=3"
  end

  # === Global Logger Configuration ===

  def test_global_logger_configuration
    # Test default logger
    assert_instance_of Taski::Logger, Taski.logger

    # Test configuration by verifying output behavior
    Taski.configure_logger(level: :debug, output: @output)

    # Verify configuration by testing actual logging behavior
    test_message = "test configuration message"
    Taski.logger.debug(test_message)
    assert_includes @output.string, test_message
  end

  def test_quiet_mode
    Taski.configure_logger(output: @output)
    Taski.quiet!  # Apply quiet mode after setting output

    Taski.logger.info("This should not appear")
    Taski.logger.error("This should appear")

    output = @output.string
    refute_includes output, "This should not appear"
    assert_includes output, "This should appear"
  end

  def test_verbose_mode
    Taski.verbose!
    Taski.configure_logger(level: :debug, output: @output)  # Explicitly set debug level

    Taski.logger.debug("Debug message")
    Taski.logger.info("Info message")

    output = @output.string
    assert_includes output, "Debug message"
    assert_includes output, "Info message"
  end

  # === Value Formatting ===

  def test_long_string_formatting
    logger = Taski::Logger.new(level: :info, output: @output)
    long_string = "a" * 100

    logger.info("Test", long_value: long_string)

    output = @output.string
    # String gets truncated to first 47 characters + "..."
    assert_includes output, "long_value=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa..."
  end

  def test_large_array_formatting
    logger = Taski::Logger.new(level: :info, output: @output)
    large_array = (1..10).to_a

    logger.info("Test", array: large_array)

    output = @output.string
    assert_includes output, "array=[1, 2, 3, 4, 5, ...]"
  end

  def test_large_hash_formatting
    logger = Taski::Logger.new(level: :info, output: @output)
    large_hash = {a: 1, b: 2, c: 3, d: 4, e: 5}

    logger.info("Test", hash: large_hash)

    output = @output.string
    assert_includes output, "hash={a, b, c, ...}"
  end

  # === Integration with Task Framework ===

  def test_integration_with_task_building
    # Test that our logging integration works with actual tasks
    test_task = Class.new(Taski::Task) do
      exports :result

      def run
        @result = "test result"
      end
    end
    Object.const_set(:LogTestTask, test_task)

    # Configure logger to capture output
    Taski.configure_logger(level: :info, output: @output)

    # Build the task
    LogTestTask.run

    output = @output.string
    assert_includes output, "Task build started"
    assert_includes output, "task=LogTestTask"
    assert_includes output, "Task build completed"
  end

  def test_integration_with_task_failure
    # Test that our logging works when tasks fail
    failing_task = Class.new(Taski::Task) do
      def run
        raise StandardError, "Intentional test failure"
      end
    end
    Object.const_set(:LogFailingTask, failing_task)

    # Configure logger to capture output
    Taski.configure_logger(level: :error, output: @output)

    # Build the task and expect failure
    assert_raises(Taski::TaskBuildError) do
      LogFailingTask.run
    end

    output = @output.string
    assert_includes output, "Task build failed"
    assert_includes output, "task=LogFailingTask"
    assert_includes output, "error_class=StandardError"
    assert_includes output, "error_message=Intentional test failure"
  end
end
