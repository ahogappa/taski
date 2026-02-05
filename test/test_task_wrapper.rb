# frozen_string_literal: true

require "test_helper"

class TestTaskWrapper < Minitest::Test
  def setup
    Taski::Task.reset! if defined?(Taski::Task)
  end

  # ========================================
  # State Constants Tests
  # ========================================

  def test_state_constants_exist
    assert_equal :pending, Taski::Execution::TaskWrapper::STATE_PENDING
    assert_equal :running, Taski::Execution::TaskWrapper::STATE_RUNNING
    assert_equal :completed, Taski::Execution::TaskWrapper::STATE_COMPLETED
    assert_equal :failed, Taski::Execution::TaskWrapper::STATE_FAILED
    assert_equal :skipped, Taski::Execution::TaskWrapper::STATE_SKIPPED
  end

  # ========================================
  # mark_skipped Tests
  # ========================================

  def test_mark_skipped_transitions_from_pending_to_skipped
    task_class = create_simple_task
    wrapper = create_wrapper(task_class)

    assert_equal :pending, wrapper.state

    result = wrapper.mark_skipped
    assert result, "mark_skipped should return true on success"
    assert_equal :skipped, wrapper.state
  end

  def test_mark_skipped_returns_false_if_not_pending
    task_class = create_simple_task
    wrapper = create_wrapper(task_class)

    # First transition to running
    wrapper.mark_running

    # mark_skipped should fail since state is now :running
    result = wrapper.mark_skipped
    refute result, "mark_skipped should return false if not pending"
    assert_equal :running, wrapper.state
  end

  def test_mark_skipped_is_terminal_state
    task_class = create_simple_task
    wrapper = create_wrapper(task_class)

    wrapper.mark_skipped

    # Cannot transition out of skipped state
    refute wrapper.mark_running, "Should not be able to transition from skipped to running"
    assert_equal :skipped, wrapper.state
  end

  def test_skipped_task_clean_state_remains_pending
    task_class = create_simple_task
    wrapper = create_wrapper(task_class)

    wrapper.mark_skipped

    # clean_state should remain pending for skipped tasks
    assert_equal :pending, wrapper.clean_state
  end

  # ========================================
  # STATE_FAILED Tests
  # ========================================

  def test_state_failed_constant_exists
    assert_equal :failed, Taski::Execution::TaskWrapper::STATE_FAILED
  end

  def test_mark_failed_transitions_to_failed_state
    task_class = create_simple_task
    wrapper = create_wrapper(task_class)

    wrapper.mark_running
    error = StandardError.new("test error")
    wrapper.mark_failed(error)

    assert_equal :failed, wrapper.state
    assert_equal error, wrapper.error
  end

  # ========================================
  # Clean State Unification Tests
  # ========================================

  def test_clean_state_getter_exists
    task_class = create_simple_task
    wrapper = create_wrapper(task_class)

    # Initial clean state should be :pending
    assert_equal :pending, wrapper.clean_state
  end

  def test_clean_running_uses_unified_state
    task_class = create_simple_task
    wrapper = create_wrapper(task_class)

    # Complete run phase first
    wrapper.mark_running
    wrapper.mark_completed("result")

    # After mark_clean_running, should be :running (not :cleaning)
    wrapper.mark_clean_running
    assert_equal :running, wrapper.clean_state
  end

  def test_clean_completed_uses_unified_state
    task_class = create_simple_task
    wrapper = create_wrapper(task_class)

    wrapper.mark_running
    wrapper.mark_completed("result")
    wrapper.mark_clean_running
    wrapper.mark_clean_completed("clean_result")

    # Should be :completed (not :clean_completed)
    assert_equal :completed, wrapper.clean_state
  end

  def test_clean_failed_uses_unified_state
    task_class = create_simple_task
    wrapper = create_wrapper(task_class)

    wrapper.mark_running
    wrapper.mark_completed("result")
    wrapper.mark_clean_running

    error = StandardError.new("clean error")
    wrapper.mark_clean_failed(error)

    # Should be :failed (not :clean_failed)
    assert_equal :failed, wrapper.clean_state
    assert_equal error, wrapper.clean_error
  end

  private

  def create_simple_task
    Class.new(Taski::Task) do
      exports :value

      def run
        @value = "done"
      end
    end
  end

  def create_wrapper(task_class)
    context = Taski::Execution::ExecutionContext.new
    registry = Taski::Execution::Registry.new
    Taski::Execution::TaskWrapper.new(task_class, registry: registry, execution_context: context)
  end
end
