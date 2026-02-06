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

  def test_mark_skipped_dispatches_notification
    task_class = create_simple_task
    events = []
    context = Taski::Execution::ExecutionFacade.new
    observer = Object.new
    observer.define_singleton_method(:on_task_updated) do |tc, previous_state:, current_state:, timestamp:|
      events << {task_class: tc, previous_state: previous_state, current_state: current_state}
    end
    context.add_observer(observer)

    wrapper = create_wrapper_with_context(task_class, context)

    wrapper.mark_skipped

    skipped_event = events.find { |e| e[:current_state] == :skipped }
    refute_nil skipped_event, "mark_skipped should dispatch task_updated notification"
    assert_equal :pending, skipped_event[:previous_state]
    assert_equal :skipped, skipped_event[:current_state]
    assert_equal task_class, skipped_event[:task_class]
  end

  def test_mark_running_dispatches_notification
    task_class = create_simple_task
    events = []
    context = Taski::Execution::ExecutionFacade.new
    observer = Object.new
    observer.define_singleton_method(:on_task_updated) do |tc, previous_state:, current_state:, timestamp:|
      events << {task_class: tc, previous_state: previous_state, current_state: current_state}
    end
    context.add_observer(observer)

    wrapper = create_wrapper_with_context(task_class, context)

    wrapper.mark_running

    running_event = events.find { |e| e[:current_state] == :running }
    refute_nil running_event, "mark_running should dispatch task_updated notification"
    assert_equal :pending, running_event[:previous_state]
    assert_equal :running, running_event[:current_state]
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
    context = Taski::Execution::ExecutionFacade.new
    registry = Taski::Execution::Registry.new
    task_instance = task_class.allocate
    task_instance.send(:initialize)
    Taski::Execution::TaskWrapper.new(task_instance, registry: registry, execution_context: context)
  end

  def create_wrapper_with_context(task_class, context)
    registry = Taski::Execution::Registry.new
    task_instance = task_class.allocate
    task_instance.send(:initialize)
    Taski::Execution::TaskWrapper.new(task_instance, registry: registry, execution_context: context)
  end
end
