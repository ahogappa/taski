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
