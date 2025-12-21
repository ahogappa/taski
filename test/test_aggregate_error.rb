# frozen_string_literal: true

require_relative "test_helper"

class TestAggregateError < Minitest::Test
  include TaskiTestHelper

  def setup
    setup_taski_test
  end

  # ========================================
  # Unit Tests for AggregateError class
  # ========================================

  # Test AggregateError message format
  def test_aggregate_error_message_format
    errors = [
      Taski::TaskFailure.new(task_class: String, error: RuntimeError.new("Error 1")),
      Taski::TaskFailure.new(task_class: Integer, error: ArgumentError.new("Error 2"))
    ]

    aggregate = Taski::AggregateError.new(errors)

    assert_includes aggregate.message, "2 tasks failed"
    assert_includes aggregate.message, "String"
    assert_includes aggregate.message, "Integer"
    assert_includes aggregate.message, "Error 1"
    assert_includes aggregate.message, "Error 2"
  end

  # Test AggregateError#cause returns the first error
  def test_aggregate_error_cause_returns_first_error
    first_error = RuntimeError.new("First")
    second_error = ArgumentError.new("Second")

    errors = [
      Taski::TaskFailure.new(task_class: String, error: first_error),
      Taski::TaskFailure.new(task_class: Integer, error: second_error)
    ]

    aggregate = Taski::AggregateError.new(errors)

    assert_equal first_error, aggregate.cause
  end

  # Test AggregateError#errors accessor
  def test_aggregate_error_errors_accessor
    errors = [
      Taski::TaskFailure.new(task_class: String, error: RuntimeError.new("Error 1")),
      Taski::TaskFailure.new(task_class: Integer, error: ArgumentError.new("Error 2"))
    ]

    aggregate = Taski::AggregateError.new(errors)

    assert_equal 2, aggregate.errors.size
    assert_equal String, aggregate.errors[0].task_class
    assert_equal Integer, aggregate.errors[1].task_class
  end

  # Test TaskFailure attributes
  def test_task_failure_attributes
    error = RuntimeError.new("Test error")
    failure = Taski::TaskFailure.new(task_class: String, error: error)

    assert_equal String, failure.task_class
    assert_equal error, failure.error
    assert_equal "Test error", failure.error.message
  end

  # Test AggregateError#includes? (like Go's errors.Is)
  def test_aggregate_error_includes
    errors = [
      Taski::TaskFailure.new(task_class: String, error: RuntimeError.new("Runtime")),
      Taski::TaskFailure.new(task_class: Integer, error: ArgumentError.new("Argument"))
    ]

    aggregate = Taski::AggregateError.new(errors)

    assert aggregate.includes?(RuntimeError)
    assert aggregate.includes?(ArgumentError)
    assert aggregate.includes?(StandardError) # Parent class
    refute aggregate.includes?(TypeError)
  end

  # Test includes? with empty errors
  def test_aggregate_error_includes_empty
    aggregate = Taski::AggregateError.new([])

    refute aggregate.includes?(RuntimeError)
  end

  # ========================================
  # AggregateAware Module Tests
  # ========================================

  # Test AggregateAware enables rescue matching with AggregateError
  def test_aggregate_aware_rescue_matching
    # Create a custom error class with AggregateAware
    custom_error_class = Class.new(StandardError) do
      extend Taski::AggregateAware
    end

    aggregate = Taski::AggregateError.new([
      Taski::TaskFailure.new(task_class: String, error: custom_error_class.new("Custom error"))
    ])

    # The custom error class should match AggregateError via ===
    assert custom_error_class === aggregate
  end

  # Test AggregateAware does not match when error type is not contained
  def test_aggregate_aware_no_match_when_not_contained
    custom_error_class = Class.new(StandardError) do
      extend Taski::AggregateAware
    end

    aggregate = Taski::AggregateError.new([
      Taski::TaskFailure.new(task_class: String, error: RuntimeError.new("Runtime"))
    ])

    # Should not match because aggregate doesn't contain custom_error_class
    refute custom_error_class === aggregate
  end

  # Test AggregateAware still works with normal exceptions
  def test_aggregate_aware_normal_exception_matching
    custom_error_class = Class.new(StandardError) do
      extend Taski::AggregateAware
    end

    normal_error = custom_error_class.new("Normal error")

    # Normal exception matching should still work
    assert custom_error_class === normal_error
    refute custom_error_class === RuntimeError.new("Other")
  end

  # Test AggregateAware works with actual rescue clause
  def test_aggregate_aware_actual_rescue
    custom_error_class = Class.new(StandardError) do
      extend Taski::AggregateAware
    end

    aggregate = Taski::AggregateError.new([
      Taski::TaskFailure.new(task_class: String, error: custom_error_class.new("Test"))
    ])

    rescued = false
    rescued_exception = nil

    begin
      raise aggregate
    rescue custom_error_class => e
      rescued = true
      rescued_exception = e
    end

    assert rescued, "Should have been rescued by custom_error_class"
    assert_instance_of Taski::AggregateError, rescued_exception
  end

  # Test AggregateAware with inheritance
  def test_aggregate_aware_with_inheritance
    parent_error = Class.new(StandardError) do
      extend Taski::AggregateAware
    end
    child_error = Class.new(parent_error)

    aggregate = Taski::AggregateError.new([
      Taski::TaskFailure.new(task_class: String, error: child_error.new("Child"))
    ])

    # Parent class should match aggregate containing child error
    assert parent_error === aggregate
  end

  # ========================================
  # TaskClass::Error Auto-generation Tests
  # ========================================

  # Test that Task subclass automatically gets an Error class
  def test_task_subclass_has_error_class
    task_class = Class.new(Taski::Task)

    assert task_class.const_defined?(:Error)
    assert task_class::Error < Taski::TaskError
  end

  # Test that TaskClass::Error wraps the original error
  def test_task_error_wraps_original_error
    original_error = RuntimeError.new("Original error")
    task_class = Class.new(Taski::Task)

    task_error = task_class::Error.new(original_error, task_class: task_class)

    assert_equal original_error, task_error.cause
    assert_equal task_class, task_error.task_class
    assert_equal "Original error", task_error.message
  end

  # Test rescuing by TaskClass::Error
  def test_rescue_by_task_error_class
    task_class = Class.new(Taski::Task) do
      exports :value

      def run
        raise "Task failed"
      end
    end

    rescued = false
    rescued_exception = nil

    begin
      task_class.value
    rescue task_class::Error => e
      rescued = true
      rescued_exception = e
    end

    assert rescued, "Should have been rescued by task_class::Error"
    assert_instance_of Taski::AggregateError, rescued_exception
  end

  # Test includes? works with TaskClass::Error
  def test_aggregate_error_includes_task_error
    task_class = Class.new(Taski::Task) do
      exports :value

      def run
        raise "Task failed"
      end
    end

    error = assert_raises(Taski::AggregateError) do
      task_class.value
    end

    assert error.includes?(task_class::Error)
    assert error.includes?(Taski::TaskError)
  end

  # ========================================
  # Integration Tests
  # ========================================

  # Test that single task failure also raises AggregateError for consistency
  def test_single_failure_raises_aggregate_error
    task_class = Class.new(Taski::Task) do
      exports :value

      def run
        raise "Single task failed"
      end
    end

    error = assert_raises(Taski::AggregateError) do
      task_class.value
    end

    assert_equal 1, error.errors.size
    assert_equal "Single task failed", error.errors.first.error.message
    assert_includes error.message, "1 tasks failed"
  end

  # Test that TaskAbortException takes priority
  def test_task_abort_exception_takes_priority
    task_class = Class.new(Taski::Task) do
      exports :value

      def run
        raise Taski::TaskAbortException, "Aborted"
      end
    end

    assert_raises(Taski::TaskAbortException) do
      task_class.value
    end
  end

  # Test error propagation is deduplicated
  def test_propagated_errors_are_deduplicated
    # Task A fails
    task_a = Class.new(Taski::Task) do
      exports :value

      def run
        raise "Task A failed"
      end
    end

    # Root task depends on A and will receive A's error
    root_task = Class.new(Taski::Task) do
      exports :result

      define_method(:run) do
        @result = task_a.value
      end
    end

    # Should raise AggregateError with only 1 error (deduplicated)
    error = assert_raises(Taski::AggregateError) do
      root_task.result
    end

    # Only 1 error because the same error object is deduplicated
    assert_equal 1, error.errors.size
    assert_equal "Task A failed", error.errors.first.error.message
  end
end
