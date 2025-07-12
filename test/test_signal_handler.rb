# frozen_string_literal: true

require_relative "test_helper"
require "stringio"

class TestSignalHandler < Minitest::Test
  include TaskiTestHelper

  def setup
    setup_taski_test
  end

  # === SignalExceptionStrategy Tests ===

  def test_interrupt_strategy_creates_correct_exception
    exception = Taski::SignalExceptionStrategy::InterruptStrategy.create_exception("INT")

    assert_instance_of Taski::TaskInterruptedException, exception
    assert_equal "interrupted by SIGINT", exception.message
  end

  def test_terminate_strategy_creates_correct_exception
    exception = Taski::SignalExceptionStrategy::TerminateStrategy.create_exception("TERM")

    assert_instance_of Taski::TaskInterruptedException, exception
    assert_equal "terminated by SIGTERM", exception.message
  end

  def test_user_signal_strategy_creates_correct_exception
    exception = Taski::SignalExceptionStrategy::UserSignalStrategy.create_exception("USR1")

    assert_instance_of Taski::TaskInterruptedException, exception
    assert_equal "user signal received: SIGUSR1", exception.message
  end

  def test_for_signal_returns_correct_strategy
    # Test known signals
    assert_equal Taski::SignalExceptionStrategy::InterruptStrategy,
      Taski::SignalExceptionStrategy.for_signal("INT")
    assert_equal Taski::SignalExceptionStrategy::TerminateStrategy,
      Taski::SignalExceptionStrategy.for_signal("TERM")
    assert_equal Taski::SignalExceptionStrategy::UserSignalStrategy,
      Taski::SignalExceptionStrategy.for_signal("USR1")
    assert_equal Taski::SignalExceptionStrategy::UserSignalStrategy,
      Taski::SignalExceptionStrategy.for_signal("USR2")
  end

  def test_for_signal_returns_default_for_unknown_signal
    # Test unknown signal returns default InterruptStrategy
    assert_equal Taski::SignalExceptionStrategy::InterruptStrategy,
      Taski::SignalExceptionStrategy.for_signal("UNKNOWN")
  end

  # === SignalHandler Tests ===

  def test_signal_handler_initialization
    handler = Taski::SignalHandler.new

    assert_equal ["INT", "TERM", "USR1"], handler.instance_variable_get(:@signals)
    assert_equal false, handler.signal_received?
    assert_nil handler.signal_name
  end

  def test_signal_handler_initialization_with_custom_signals
    custom_signals = ["INT", "TERM"]
    handler = Taski::SignalHandler.new(signals: custom_signals)

    assert_equal custom_signals, handler.instance_variable_get(:@signals)
  end

  def test_convert_signal_to_exception
    handler = Taski::SignalHandler.new

    exception = handler.convert_signal_to_exception("INT")
    assert_instance_of Taski::TaskInterruptedException, exception
    assert_equal "interrupted by SIGINT", exception.message
  end

  def test_setup_signal_traps_skips_during_tests
    # Test that setup_signal_traps returns early during tests
    handler = Taski::SignalHandler.new

    # Mock Signal.trap to ensure it's not called
    signal_trap_called = false
    Signal.stub(:trap, ->(_signal) { signal_trap_called = true }) do
      handler.setup_signal_traps
    end

    # Signal.trap should not be called because we're in test environment
    assert_equal false, signal_trap_called
  end

  def test_setup_signal_traps_in_non_test_environment
    # This test verifies that signal trapping occurs when not in test environment
    # We'll test this by temporarily modifying the handler to skip the test check
    handler = Taski::SignalHandler.new

    trapped_signals = []
    Signal.stub(:trap, ->(signal) { trapped_signals << signal }) do
      # Call the private method directly to bypass test environment check
      handler.instance_variable_get(:@signals).each do |signal|
        handler.send(:setup_signal_trap, signal)
      end
    end

    assert_equal ["INT", "TERM", "USR1"], trapped_signals
  end

  def test_signal_handler_callback_sets_state
    handler = Taski::SignalHandler.new
    trapped_blocks = {}

    # Capture the blocks passed to Signal.trap
    Signal.stub(:trap, ->(signal, &block) { trapped_blocks[signal] = block }) do
      # Call setup_signal_trap directly to bypass test environment check
      handler.instance_variable_get(:@signals).each do |signal|
        handler.send(:setup_signal_trap, signal)
      end
    end

    # Simulate receiving a signal by calling the trapped block
    trapped_blocks["INT"].call

    assert_equal true, handler.signal_received?
    assert_equal "INT", handler.signal_name
  end

  def test_signal_trap_handles_argument_error
    handler = Taski::SignalHandler.new(signals: ["INVALID_SIGNAL"])

    # Mock Signal.trap to raise ArgumentError and capture stderr output
    Signal.stub(:trap, ->(_signal) { raise ArgumentError, "Invalid signal" }) do
      # Capture stderr output where warnings are written
      original_stderr = $stderr
      $stderr = StringIO.new

      # Call setup_signal_trap directly to test error handling
      handler.send(:setup_signal_trap, "INVALID_SIGNAL")

      warning_output = $stderr.string
      $stderr = original_stderr

      assert_includes warning_output, "Warning: Unable to trap signal INVALID_SIGNAL"
      assert_includes warning_output, "Invalid signal"
    end
  end

  def test_class_method_setup_signal_traps
    # Test that class method creates instance and sets up signal traps
    # Since we're in test environment, we verify the instance is created correctly
    handler_instance = nil
    Taski::SignalHandler.stub(:new, ->(signals: Taski::SignalHandler::DEFAULT_SIGNALS) {
      handler_instance = Taski::SignalHandler.allocate
      handler_instance.send(:initialize, signals: signals)
      handler_instance
    }) do
      Taski::SignalHandler.setup_signal_traps
    end

    assert_instance_of Taski::SignalHandler, handler_instance
    assert_equal ["INT", "TERM", "USR1"], handler_instance.instance_variable_get(:@signals)
  end

  def test_class_method_setup_signal_traps_with_custom_signals
    custom_signals = ["INT", "TERM"]

    # Test that class method creates instance with custom signals
    handler_instance = nil
    Taski::SignalHandler.stub(:new, ->(signals:) {
      handler_instance = Taski::SignalHandler.allocate
      handler_instance.send(:initialize, signals: signals)
      handler_instance
    }) do
      Taski::SignalHandler.setup_signal_traps(signals: custom_signals)
    end

    assert_instance_of Taski::SignalHandler, handler_instance
    assert_equal custom_signals, handler_instance.instance_variable_get(:@signals)
  end

  # === Signal Handler Integration Tests ===

  def test_signal_handler_integration_with_task_execution
    # Test that signal handling is properly integrated with task execution
    # We'll test by stubbing the signal handler to simulate signal reception
    handler_instance = nil
    signal_received = false

    # Create a test task
    test_task_class = Class.new(Taski::Task) do
      def run
        # Simple task that just returns a value
        "task completed"
      end
    end
    Object.const_set(:SignalIntegrationTestTask, test_task_class)

    # Stub SignalHandler creation to capture the instance
    original_new = Taski::SignalHandler.method(:new)
    Taski::SignalHandler.define_singleton_method(:new) do |*args|
      handler_instance = original_new.call(*args)
      # Stub the signal_received? method to simulate signal reception
      handler_instance.define_singleton_method(:signal_received?) { signal_received }
      handler_instance.define_singleton_method(:signal_name) { "INT" }
      handler_instance
    end

    begin
      # Test normal execution (no signal)
      result = Taski::InstanceBuilder.with_build_logging("SignalIntegrationTestTask") do
        "normal execution"
      end
      assert_equal "normal execution", result

      # Test signal interruption
      signal_received = true
      error = assert_raises(Taski::TaskInterruptedException) do
        Taski::InstanceBuilder.with_build_logging("SignalIntegrationTestTask") do
          "should be interrupted"
        end
      end
      assert_equal "interrupted by SIGINT", error.message
    ensure
      # Restore original method
      Taski::SignalHandler.define_singleton_method(:new, &original_new)
      Object.send(:remove_const, :SignalIntegrationTestTask)
    end
  end

  def test_task_interrupted_exception_special_handling
    # Test that TaskInterruptedException receives special handling in progress display
    progress_calls = []

    # Mock progress display to capture method calls
    original_progress_display = Taski.progress_display
    mock_progress = Object.new
    mock_progress.define_singleton_method(:start_task) { |*args| progress_calls << [:start_task, args] }
    mock_progress.define_singleton_method(:interrupt_task) { |*args| progress_calls << [:interrupt_task, args] }
    mock_progress.define_singleton_method(:fail_task) { |*args| progress_calls << [:fail_task, args] }

    Taski.instance_variable_set(:@progress_display, mock_progress)

    # Stub signal handler to simulate signal reception
    handler_instance = nil
    Taski::SignalHandler.stub(:new, proc {
      handler_instance = Taski::SignalHandler.allocate
      handler_instance.send(:initialize)
      handler_instance.define_singleton_method(:setup_signal_traps) {}
      handler_instance.define_singleton_method(:signal_received?) { true }
      handler_instance.define_singleton_method(:signal_name) { "TERM" }
      handler_instance
    }) do
      assert_raises(Taski::TaskInterruptedException) do
        Taski::InstanceBuilder.with_build_logging("TestTask") do
          "task execution"
        end
      end
    end

    # Verify interrupt_task was called, not fail_task
    interrupt_calls = progress_calls.select { |call| call[0] == :interrupt_task }
    fail_calls = progress_calls.select { |call| call[0] == :fail_task }

    assert_equal 1, interrupt_calls.length, "interrupt_task should be called once"
    assert_equal 0, fail_calls.length, "fail_task should not be called for TaskInterruptedException"

    # Verify the error passed to interrupt_task is TaskInterruptedException
    interrupt_args = interrupt_calls.first[1]
    error = interrupt_args[1][:error]  # Second argument hash, :error key
    assert_instance_of Taski::TaskInterruptedException, error
    assert_equal "terminated by SIGTERM", error.message
  ensure
    Taski.instance_variable_set(:@progress_display, original_progress_display)
  end

  def test_signal_handler_respects_test_environment
    # Verify that signal trapping is skipped in test environment
    # This is important to ensure our tests don't interfere with each other

    trapped_signals = []
    Signal.stub(:trap, ->(signal) { trapped_signals << signal }) do
      # Even though we stub Signal.trap, it shouldn't be called in test environment
      Taski::InstanceBuilder.with_build_logging("TestTask") do
        "test execution"
      end
    end

    # No signals should be trapped because we're in test environment
    assert_empty trapped_signals, "Signal trapping should be skipped in test environment"
  end
end
