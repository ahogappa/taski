# frozen_string_literal: true

require "test_helper"

class TestTaskObserver < Minitest::Test
  def test_responds_to_all_event_methods
    observer = Taski::Execution::TaskObserver.new

    assert_respond_to observer, :on_ready
    assert_respond_to observer, :on_start
    assert_respond_to observer, :on_stop
    assert_respond_to observer, :on_task_updated
    assert_respond_to observer, :on_group_started
    assert_respond_to observer, :on_group_completed
  end

  def test_context_accessor
    observer = Taski::Execution::TaskObserver.new
    assert_nil observer.context

    mock_context = Object.new
    observer.context = mock_context
    assert_equal mock_context, observer.context
  end

  def test_all_event_methods_are_noop
    observer = Taski::Execution::TaskObserver.new
    now = Time.now

    # None of these should raise
    observer.on_ready
    observer.on_start
    observer.on_stop
    observer.on_task_updated(String, previous_state: :pending, current_state: :running, phase: :run, timestamp: now)
    observer.on_group_started(String, "setup", phase: :run, timestamp: now)
    observer.on_group_completed(String, "setup", phase: :run, timestamp: now)
  end

  def test_subclass_overriding_single_method_keeps_other_noop_defaults
    subclass = Class.new(Taski::Execution::TaskObserver) do
      attr_reader :updated_args

      def on_task_updated(task_class, previous_state:, current_state:, phase:, timestamp:)
        @updated_args = {task_class: task_class, current_state: current_state}
      end
    end

    observer = subclass.new
    now = Time.now

    # Overridden method works
    observer.on_task_updated(String, previous_state: :pending, current_state: :running, phase: :run, timestamp: now)
    assert_equal({task_class: String, current_state: :running}, observer.updated_args)

    # Non-overridden methods remain no-ops (don't raise)
    observer.on_ready
    observer.on_start
    observer.on_stop
    observer.on_group_started(String, "setup", phase: :run, timestamp: now)
    observer.on_group_completed(String, "setup", phase: :run, timestamp: now)
  end

  def test_integrates_with_execution_facade_add_observer
    facade = Taski::Execution::ExecutionFacade.new(root_task_class: String)
    observer = Taski::Execution::TaskObserver.new

    facade.add_observer(observer)

    # context should be auto-injected
    assert_equal facade, observer.context
    assert_includes facade.observers, observer
  end

  def test_subclass_receives_context_via_facade
    subclass = Class.new(Taski::Execution::TaskObserver) do
      attr_reader :ready_called

      def on_ready
        @ready_called = true
      end
    end

    facade = Taski::Execution::ExecutionFacade.new(root_task_class: String)
    observer = subclass.new

    facade.add_observer(observer)
    facade.notify_ready

    assert_equal facade, observer.context
    assert observer.ready_called
  end
end
