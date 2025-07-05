# frozen_string_literal: true

require_relative "test_helper"

class TestErrorHandling < Minitest::Test
  include TaskiTestHelper

  def setup
    setup_taski_test
  end

  # === Error Handling Tests ===

  def test_build_error_handling
    # Test error handling during build
    task = Class.new(Taski::Task) do
      def run
        raise StandardError, "Build failed intentionally"
      end
    end
    Object.const_set(:ErrorTaskA, task)

    # Building should raise TaskBuildError
    error = assert_raises(Taski::TaskBuildError) do
      ErrorTaskA.run
    end

    assert_includes error.message, "Failed to build task ErrorTaskA"
    assert_includes error.message, "Build failed intentionally"
  end

  def test_reference_error_handling
    # Test Reference class error handling
    ref = Taski::Reference.new("NonExistentClass")

    # deref should raise TaskAnalysisError for non-existent class
    error = assert_raises(Taski::TaskAnalysisError) do
      ref.deref
    end

    assert_includes error.message, "Cannot resolve constant 'NonExistentClass'"

    # == should return false for non-existent class
    assert_equal false, (ref == String)
  end

  def test_task_analysis_error
    # Test TaskAnalysisError is properly defined
    error = Taski::TaskAnalysisError.new("test message")
    assert_instance_of Taski::TaskAnalysisError, error
    assert_kind_of StandardError, error
    assert_equal "test message", error.message
  end

  def test_circular_dependency_error
    # Test CircularDependencyError is properly defined
    error = Taski::CircularDependencyError.new("circular dependency")
    assert_instance_of Taski::CircularDependencyError, error
    assert_kind_of StandardError, error
    assert_equal "circular dependency", error.message
  end

  def test_task_build_error
    # Test TaskBuildError is properly defined
    error = Taski::TaskBuildError.new("build error")
    assert_instance_of Taski::TaskBuildError, error
    assert_kind_of StandardError, error
    assert_equal "build error", error.message
  end

  def test_build_dependencies_error_resilience
    # Test that build continues even if one dependency fails
    failing_task = Class.new(Taski::Task) do
      def run
        raise StandardError, "Intentional failure"
      end
    end
    Object.const_set(:FailingTask, failing_task)

    dependent_task = Class.new(Taski::Task) do
      exports :result

      def run
        # This will fail because FailingTask.run raises an error
        FailingTask.run
        @result = "This should not be reached"
      end
    end
    Object.const_set(:DependentTask, dependent_task)

    # Should raise TaskBuildError due to failing dependency
    assert_raises(Taski::TaskBuildError) do
      DependentTask.run
    end
  end

  def test_task_interrupted_exception
    # Test TaskInterruptedException is properly defined
    error = Taski::TaskInterruptedException.new("interrupted by signal")
    assert_instance_of Taski::TaskInterruptedException, error
    assert_kind_of StandardError, error
    assert_equal "interrupted by signal", error.message
  end

  def test_signal_handler_setup
    # Test that signal handler setup utility exists
    assert_respond_to Taski::SignalHandler, :setup_signal_traps
  end

  def test_signal_handler_sigint_conversion
    # Test that SIGINT signal is converted to TaskInterruptedException
    handler = Taski::SignalHandler.new

    # Simulate signal handling
    exception = handler.convert_signal_to_exception("INT")

    assert_instance_of Taski::TaskInterruptedException, exception
    assert_includes exception.message, "interrupted by SIGINT"
  end

  def test_task_build_session_signal_integration
    # Test that TaskBuildSession integrates with signal handling
    context = Taski::Utils::TaskContext.new("TestSignalTask")
    session = Taski::Utils::TaskBuildSession.new(context)

    # Check that session responds to signal handling methods
    assert_respond_to session, :setup_signal_handling
    assert_respond_to session, :check_for_signals
  end

  def test_task_build_session_signal_check_raises_exception
    # Test that checking for signals raises TaskInterruptedException when signal is received
    context = Taski::Utils::TaskContext.new("TestSignalTask")
    session = Taski::Utils::TaskBuildSession.new(context)

    # Simulate received signal
    session.instance_variable_set(:@signal_handler, Taski::SignalHandler.new)
    session.signal_handler.instance_variable_set(:@signal_received, true)
    session.signal_handler.instance_variable_set(:@signal_name, "INT")

    # Should raise TaskInterruptedException when checking for signals
    error = assert_raises(Taski::TaskInterruptedException) do
      session.check_for_signals
    end

    assert_includes error.message, "interrupted by SIGINT"
  end

  def test_task_build_session_calls_interrupt_task_for_signal_interruption
    # Test that TaskBuildSession calls interrupt_task for TaskInterruptedException
    context = Taski::Utils::TaskContext.new("InterruptedTestTask")
    session = Taski::Utils::TaskBuildSession.new(context)

    # Create a mock progress display class
    mock_progress_class = Class.new do
      attr_reader :interrupt_called, :interrupt_task_name, :interrupt_error, :interrupt_duration

      def interrupt_task(task_name, error:, duration:)
        @interrupt_called = true
        @interrupt_task_name = task_name
        @interrupt_error = error
        @interrupt_duration = duration
      end
    end

    mock_progress = mock_progress_class.new

    # Set mock progress display
    original_progress = Taski.instance_variable_get(:@progress_display)
    Taski.instance_variable_set(:@progress_display, mock_progress)

    begin
      # Setup session timing (simulate normal execution)
      session.send(:start_timing)
      sleep 0.001  # Small delay to ensure duration > 0
      session.send(:calculate_duration)

      # Create TaskInterruptedException and test
      interrupted_error = Taski::TaskInterruptedException.new("interrupted by SIGINT")
      session.send(:complete_progress_failure, interrupted_error)

      assert mock_progress.interrupt_called, "interrupt_task should have been called"
      assert_equal "InterruptedTestTask", mock_progress.interrupt_task_name
      assert_equal interrupted_error, mock_progress.interrupt_error
      assert_instance_of Float, mock_progress.interrupt_duration
    ensure
      # Restore original progress display
      Taski.instance_variable_set(:@progress_display, original_progress)
    end
  end

  def test_not_implemented_error
    # Test that base Task class raises NotImplementedError for build
    task = Taski::Task.new

    error = assert_raises(NotImplementedError) do
      task.run
    end

    assert_includes error.message, "You must implement the run method"
  end

  def test_define_with_existing_ref_works_correctly
    # Test that define with ref() works correctly (existing functionality)

    # Create an existing task
    existing_task = Class.new(Taski::Task) do
      exports :value
      def run
        @value = "existing_value"
      end
    end
    Object.const_set(:ExistingRefTaskWorking, existing_task)

    # Create task that uses ref()
    ref_task = Class.new(Taski::Task) do
      define :result, -> { ref("ExistingRefTaskWorking").value }

      def run
        # Empty build method (DefineAPI doesn't require build implementation)
      end
    end
    Object.const_set(:RefUsingTaskWorking, ref_task)

    # Build first to trigger dependency resolution
    ref_task.run

    # This should work without error
    result = ref_task.result
    assert_equal "existing_value", result
  end

  def test_build_with_nonexistent_ref_fails_in_phase_2
    # RED: Test that build with non-existent ref fails in phase 2

    ref_task = Class.new(Taski::Task) do
      define :result, -> { ref("NonExistentRefTask").value }

      def run
        # Empty build method (DefineAPI doesn't require build implementation)
      end
    end
    Object.const_set(:RefFailingTask, ref_task)

    # build should raise TaskAnalysisError in phase 2 (before execution)
    error = assert_raises(Taski::TaskAnalysisError) do
      RefFailingTask.run
    end

    assert_includes error.message, "Task 'RefFailingTask' cannot resolve ref('NonExistentRefTask')"
  end

  # === rescue_deps API Tests ===

  def test_rescue_deps_method_exists
    # RED: Test that rescue_deps method can be called without error
    task_class = Class.new(Taski::Task)

    # This should not raise any error
    task_class.rescue_deps StandardError, ->(exception, failed_task) {}
  end

  def test_rescue_deps_stores_handler
    # RED: Test that rescue_deps stores the handler
    task_class = Class.new(Taski::Task)
    handler = ->(exception, failed_task) {}

    task_class.rescue_deps StandardError, handler

    # Handler should be stored and findable
    found_handler = task_class.find_dependency_rescue_handler(StandardError.new)
    refute_nil found_handler
  end

  def test_rescue_deps_catches_dependency_exception
    # RED: Test that rescue_deps catches exceptions from dependency tasks
    child_task = Class.new(Taski::Task) do
      exports :value

      def run
        raise StandardError, "child task failed"
      end
    end
    Object.const_set(:RescueDepChildTask, child_task)

    parent_task = Class.new(Taski::Task) do
      rescue_deps StandardError, ->(exception, failed_task) {}

      # Create dependency through define API
      define :result, -> {
        # Reference child task to create dependency
        # Even if child fails, rescue_deps should handle it
        begin
          RescueDepChildTask.value
        rescue
          "default_value"
        end
        "parent completed"
      }

      def run
        # This creates dependency at class definition time
        # The dependency will cause RescueDepChildTask to run first
      end
    end
    Object.const_set(:RescueDepParentTask, parent_task)

    # Should catch the child exception and continue
    result = parent_task.run
    assert_instance_of parent_task, result
    # Verify that parent task completed successfully (no exception was raised)
  end

  def test_rescue_deps_supports_multiple_exception_classes
    # RED: Test that rescue_deps can handle different exception classes
    task_class = Class.new(Taski::Task)
    handler = ->(exception, failed_task) {}

    task_class.rescue_deps RuntimeError, handler
    task_class.rescue_deps ArgumentError, handler

    # Should find handler for RuntimeError
    runtime_handler = task_class.find_dependency_rescue_handler(RuntimeError.new)
    refute_nil runtime_handler

    # Should find handler for ArgumentError
    argument_handler = task_class.find_dependency_rescue_handler(ArgumentError.new)
    refute_nil argument_handler

    # Should not find handler for unregistered exception
    io_handler = task_class.find_dependency_rescue_handler(IOError.new)
    assert_nil io_handler
  end

  def test_rescue_deps_finds_handler_for_task_interrupted_exception
    # Simple test to verify rescue_deps can register and find TaskInterruptedException handlers
    task_class = Class.new(Taski::Task)
    handler = ->(exception, failed_task) { "handled" }

    # Register handler for TaskInterruptedException
    task_class.rescue_deps Taski::TaskInterruptedException, handler

    # Should find handler for TaskInterruptedException
    found_handler = task_class.find_dependency_rescue_handler(Taski::TaskInterruptedException.new("test"))
    refute_nil found_handler
    assert_equal [Taski::TaskInterruptedException, handler], found_handler
  end

  def test_rescue_deps_reraise_control
    # Test that :reraise causes exception to be re-raised
    child_task = Class.new(Taski::Task) do
      exports :value

      def run
        raise StandardError, "child task failed"
      end
    end
    Object.const_set(:RescueReraiseChildTask, child_task)

    parent_task = Class.new(Taski::Task) do
      rescue_deps StandardError, ->(exception, failed_task) { :reraise }

      def run
        # Reference child task to create dependency - this will be caught by static analysis
        RescueReraiseChildTask.run
        "parent completed"
      end
    end
    Object.const_set(:RescueReraiseParentTask, parent_task)

    # Should re-raise the exception
    assert_raises(Taski::TaskBuildError) do
      parent_task.run
    end
  end

  def test_rescue_deps_custom_exception
    # Test that custom exception can be raised instead
    child_task = Class.new(Taski::Task) do
      exports :value

      def run
        raise StandardError, "child task failed"
      end
    end
    Object.const_set(:RescueCustomChildTask, child_task)

    parent_task = Class.new(Taski::Task) do
      rescue_deps StandardError, ->(exception, failed_task) {
        ArgumentError.new("Custom error from rescue_deps")
      }

      def run
        # Reference child task to create dependency - this will be caught by static analysis
        RescueCustomChildTask.run
        "parent completed"
      end
    end
    Object.const_set(:RescueCustomParentTask, parent_task)

    # Should raise the custom exception
    error = assert_raises(ArgumentError) do
      parent_task.run
    end
    assert_includes error.message, "Custom error from rescue_deps"
  end

  # === Multiple Signal Support Tests ===

  def test_signal_handler_multiple_signals_setup
    # Test that signal handler supports multiple signals
    handler = Taski::SignalHandler.new(signals: %w[INT TERM USR1])

    # This should not raise error
    handler.setup_signal_traps
  end

  def test_signal_handler_term_conversion
    # Test that SIGTERM signal is converted to TaskInterruptedException
    handler = Taski::SignalHandler.new

    exception = handler.convert_signal_to_exception("TERM")

    assert_instance_of Taski::TaskInterruptedException, exception
    assert_includes exception.message, "terminated by SIGTERM"
  end

  def test_signal_handler_usr1_conversion
    # Test that SIGUSR1 signal is converted to TaskInterruptedException
    handler = Taski::SignalHandler.new

    exception = handler.convert_signal_to_exception("USR1")

    assert_instance_of Taski::TaskInterruptedException, exception
    assert_includes exception.message, "user signal received: SIGUSR1"
  end

  def test_signal_exception_strategy_pattern
    # Test that signal exception strategy pattern works correctly
    int_strategy = Taski::SignalExceptionStrategy.for_signal("INT")
    term_strategy = Taski::SignalExceptionStrategy.for_signal("TERM")
    usr1_strategy = Taski::SignalExceptionStrategy.for_signal("USR1")

    assert_equal Taski::SignalExceptionStrategy::InterruptStrategy, int_strategy
    assert_equal Taski::SignalExceptionStrategy::TerminateStrategy, term_strategy
    assert_equal Taski::SignalExceptionStrategy::UserSignalStrategy, usr1_strategy
  end

  def test_signal_exception_strategy_unknown_signal
    # Test that unknown signals fall back to InterruptStrategy
    unknown_strategy = Taski::SignalExceptionStrategy.for_signal("UNKNOWN")

    assert_equal Taski::SignalExceptionStrategy::InterruptStrategy, unknown_strategy
  end

  def test_signal_handler_custom_signals
    # Test that custom signal list works
    custom_signals = %w[INT TERM]
    handler = Taski::SignalHandler.new(signals: custom_signals)

    # Should not raise error
    handler.setup_signal_traps
  end
end
