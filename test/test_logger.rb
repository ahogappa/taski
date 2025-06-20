# frozen_string_literal: true

require_relative "test_helper"
require "stringio"

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
    mock_task_a = Class.new { def self.name; "TaskA"; end }
    mock_task_b = Class.new { def self.name; "TaskB"; end }
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
    
    # Test configuration
    Taski.configure_logger(level: :debug, output: @output)
    assert_equal @output, Taski.logger.instance_variable_get(:@output)
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
    large_hash = { a: 1, b: 2, c: 3, d: 4, e: 5 }
    
    logger.info("Test", hash: large_hash)
    
    output = @output.string
    assert_includes output, "hash={a, b, c, ...}"
  end

  # === Integration with Task Framework ===

  def test_integration_with_task_building
    # Test that our logging integration works with actual tasks
    test_task = Class.new(Taski::Task) do
      exports :result

      def build
        @result = "test result"
      end
    end
    Object.const_set(:LogTestTask, test_task)

    # Configure logger to capture output
    Taski.configure_logger(level: :info, output: @output)

    # Build the task
    LogTestTask.build

    output = @output.string
    assert_includes output, "Task build started"
    assert_includes output, "task=LogTestTask"
    assert_includes output, "Task build completed"
  end

  def test_integration_with_task_failure
    # Test that our logging works when tasks fail
    failing_task = Class.new(Taski::Task) do
      def build
        raise StandardError, "Intentional test failure"
      end
    end
    Object.const_set(:LogFailingTask, failing_task)

    # Configure logger to capture output
    Taski.configure_logger(level: :error, output: @output)

    # Build the task and expect failure
    assert_raises(Taski::TaskBuildError) do
      LogFailingTask.build
    end

    output = @output.string
    assert_includes output, "Task build failed"
    assert_includes output, "task=LogFailingTask"
    assert_includes output, "error_class=StandardError"
    assert_includes output, "error_message=Intentional test failure"
  end
end