# frozen_string_literal: true

require "test_helper"

class TestTaskObserver < Minitest::Test
  def test_context_accessor
    observer = Taski::Execution::TaskObserver.new
    assert_nil observer.facade

    mock_context = Object.new
    observer.facade = mock_context
    assert_equal mock_context, observer.facade
  end

  def test_has_default_empty_implementations
    observer = Taski::Execution::TaskObserver.new

    # All methods should exist and do nothing (return nil)
    assert_nil observer.on_ready
    assert_nil observer.on_start
    assert_nil observer.on_stop
    assert_nil observer.on_phase_started(:run)
    assert_nil observer.on_phase_completed(:run)
    assert_nil observer.on_task_updated(String, previous_state: :pending, current_state: :running, timestamp: Time.now)
    assert_nil observer.on_group_started(String, "group_name")
    assert_nil observer.on_group_completed(String, "group_name")
  end

  def test_subclass_can_override_methods
    custom_observer = Class.new(Taski::Execution::TaskObserver) do
      attr_reader :events

      def initialize
        super
        @events = []
      end

      def on_ready
        @events << :ready
      end

      def on_task_updated(task_class, previous_state:, current_state:, timestamp:)
        @events << [:task_updated, task_class, previous_state, current_state]
      end
    end.new

    custom_observer.on_ready
    custom_observer.on_task_updated(String, previous_state: :pending, current_state: :running, timestamp: Time.now)

    assert_equal :ready, custom_observer.events[0]
    assert_equal [:task_updated, String, :pending, :running], custom_observer.events[1]
  end
end

class TestExecutionContextObserverInjection < Minitest::Test
  def test_add_observer_injects_context
    context = Taski::Execution::ExecutionContext.new
    observer = Taski::Execution::TaskObserver.new

    assert_nil observer.facade

    context.add_observer(observer)

    assert_equal context, observer.facade
  end

  def test_add_observer_works_with_non_task_observer
    context = Taski::Execution::ExecutionContext.new
    # Plain object without context= method
    observer = Object.new

    # Should not raise
    context.add_observer(observer)
    assert_includes context.observers, observer
  end
end

class TestNotifyNewEvents < Minitest::Test
  def setup
    @context = Taski::Execution::ExecutionContext.new
    @events = []
    @observer = create_recording_observer
    @context.add_observer(@observer)
  end

  def test_notify_ready_calls_on_ready
    @context.notify_ready

    assert_equal [[:on_ready]], @events
  end

  def test_notify_phase_started_calls_on_phase_started
    @context.notify_phase_started(:run)

    assert_equal [[:on_phase_started, :run]], @events
  end

  def test_notify_phase_completed_calls_on_phase_completed
    @context.notify_phase_completed(:run)

    assert_equal [[:on_phase_completed, :run]], @events
  end

  def test_notify_task_updated_calls_on_task_updated
    timestamp = Time.now
    @context.notify_task_updated(String, previous_state: :pending, current_state: :running, timestamp: timestamp)

    assert_equal 1, @events.size
    event = @events.first
    assert_equal :on_task_updated, event[0]
    assert_equal String, event[1]
    assert_equal :pending, event[2][:previous_state]
    assert_equal :running, event[2][:current_state]
    assert_equal timestamp, event[2][:timestamp]
  end

  def test_notify_task_updated_for_failed_state
    # Note: error is NOT passed via notification - exceptions propagate to top level (Plan design)
    timestamp = Time.now
    @context.notify_task_updated(String, previous_state: :running, current_state: :failed, timestamp: timestamp)

    assert_equal 1, @events.size
    event = @events.first
    assert_equal :failed, event[2][:current_state]
    assert_equal timestamp, event[2][:timestamp]
  end

  private

  def create_recording_observer
    events = @events
    Class.new(Taski::Execution::TaskObserver) do
      define_method(:on_ready) { events << [:on_ready] }
      define_method(:on_phase_started) { |phase| events << [:on_phase_started, phase] }
      define_method(:on_phase_completed) { |phase| events << [:on_phase_completed, phase] }
      define_method(:on_task_updated) do |task_class, previous_state:, current_state:, timestamp:|
        events << [:on_task_updated, task_class, {previous_state:, current_state:, timestamp:}]
      end
    end.new
  end
end
