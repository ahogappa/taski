# frozen_string_literal: true

require "test_helper"

class TestExecutionContext < Minitest::Test
  def setup
    Taski::Task.reset! if defined?(Taski::Task)
  end

  # Test thread-local current context
  def test_current_context_thread_local
    context = Taski::Execution::ExecutionContext.new

    assert_nil Taski::Execution::ExecutionContext.current

    Taski::Execution::ExecutionContext.current = context
    assert_equal context, Taski::Execution::ExecutionContext.current

    Taski::Execution::ExecutionContext.current = nil
    assert_nil Taski::Execution::ExecutionContext.current
  end

  # Test observer management
  def test_add_and_remove_observer
    context = Taski::Execution::ExecutionContext.new
    observer = Object.new

    context.add_observer(observer)
    assert_includes context.observers, observer

    context.remove_observer(observer)
    refute_includes context.observers, observer
  end

  def test_observers_returns_copy
    context = Taski::Execution::ExecutionContext.new
    observer = Object.new
    context.add_observer(observer)

    observers_copy = context.observers
    observers_copy.clear

    # Original should still have the observer
    assert_includes context.observers, observer
  end

  # Test observer notifications
  def test_notify_task_registered
    context = Taski::Execution::ExecutionContext.new
    called_with = nil
    observer = Object.new
    observer.define_singleton_method(:register_task) do |task_class|
      called_with = task_class
    end

    context.add_observer(observer)
    context.notify_task_registered(String)

    assert_equal String, called_with
  end

  def test_notify_task_started
    context = Taski::Execution::ExecutionContext.new
    called_with = nil
    observer = Object.new
    observer.define_singleton_method(:update_task) do |task_class, state:, **_kwargs|
      called_with = {task_class: task_class, state: state}
    end

    context.add_observer(observer)
    context.notify_task_started(String)

    assert_equal({task_class: String, state: :running}, called_with)
  end

  def test_notify_task_completed_success
    context = Taski::Execution::ExecutionContext.new
    called_with = nil
    observer = Object.new
    observer.define_singleton_method(:update_task) do |task_class, state:, duration:, error:|
      called_with = {task_class: task_class, state: state, duration: duration, error: error}
    end

    context.add_observer(observer)
    context.notify_task_completed(String, duration: 1.5)

    assert_equal String, called_with[:task_class]
    assert_equal :completed, called_with[:state]
    assert_equal 1.5, called_with[:duration]
    assert_nil called_with[:error]
  end

  def test_notify_task_completed_with_error
    context = Taski::Execution::ExecutionContext.new
    called_with = nil
    observer = Object.new
    observer.define_singleton_method(:update_task) do |task_class, state:, duration:, error:|
      called_with = {task_class: task_class, state: state, duration: duration, error: error}
    end

    test_error = StandardError.new("test error")
    context.add_observer(observer)
    context.notify_task_completed(String, error: test_error)

    assert_equal :failed, called_with[:state]
    assert_equal test_error, called_with[:error]
  end

  def test_notify_set_root_task
    context = Taski::Execution::ExecutionContext.new
    called_with = nil
    observer = Object.new
    observer.define_singleton_method(:set_root_task) do |task_class|
      called_with = task_class
    end

    context.add_observer(observer)
    context.notify_set_root_task(String)

    assert_equal String, called_with
  end

  def test_notify_start_and_stop
    context = Taski::Execution::ExecutionContext.new
    start_called = false
    stop_called = false
    observer = Object.new
    observer.define_singleton_method(:start) { start_called = true }
    observer.define_singleton_method(:stop) { stop_called = true }

    context.add_observer(observer)

    context.notify_start
    assert start_called

    context.notify_stop
    assert stop_called
  end

  # Test dispatch handles observer exceptions gracefully
  def test_dispatch_handles_observer_exception
    context = Taski::Execution::ExecutionContext.new

    first_called = false
    second_called = false

    first_observer = Object.new
    first_observer.define_singleton_method(:register_task) do |_task_class|
      first_called = true
      raise "Observer error"
    end

    second_observer = Object.new
    second_observer.define_singleton_method(:register_task) do |_task_class|
      second_called = true
    end

    context.add_observer(first_observer)
    context.add_observer(second_observer)

    # Should not raise, and second observer should still be called
    _out, err = capture_io do
      context.notify_task_registered(String)
    end

    assert first_called
    assert second_called
    assert_match(/Observer.*raised error/, err)
  end

  # Test dispatch skips observers that don't respond to method
  def test_dispatch_skips_non_responding_observers
    context = Taski::Execution::ExecutionContext.new
    observer = Object.new # No methods defined

    context.add_observer(observer)

    # Should not raise
    context.notify_task_registered(String)
  end

  # Test execution trigger
  def test_execution_trigger_with_custom_trigger
    context = Taski::Execution::ExecutionContext.new
    triggered_with = nil

    context.execution_trigger = ->(task_class, registry) do
      triggered_with = {task_class: task_class, registry: registry}
    end

    registry = Taski::Execution::Registry.new
    context.trigger_execution(String, registry: registry)

    assert_equal String, triggered_with[:task_class]
    assert_equal registry, triggered_with[:registry]
  end

  def test_execution_trigger_fallback
    context = Taski::Execution::ExecutionContext.new

    task_class = Class.new(Taski::Task) do
      exports :value
      def run
        @value = "fallback_test"
      end
    end

    registry = Taski::Execution::Registry.new
    context.trigger_execution(task_class, registry: registry)

    wrapper = registry.get_task(task_class)
    assert wrapper.completed?
  end

  # Test output capture with TTY
  def test_setup_output_capture_with_tty
    context = Taski::Execution::ExecutionContext.new

    # Create a mock TTY IO
    mock_io = StringIO.new
    mock_io.define_singleton_method(:tty?) { true }

    set_capture_called = false
    observer = Object.new
    observer.define_singleton_method(:set_output_capture) do |_capture|
      set_capture_called = true
    end
    context.add_observer(observer)

    original_stdout = $stdout
    begin
      context.setup_output_capture(mock_io)

      assert set_capture_called
      refute_nil context.output_capture
      assert_kind_of Taski::Execution::TaskOutputRouter, $stdout

      context.teardown_output_capture
      assert_nil context.output_capture
    ensure
      $stdout = original_stdout
    end
  end

  def test_setup_output_capture_always_sets_capture
    context = Taski::Execution::ExecutionContext.new

    # setup_output_capture now always sets up capture when called
    # The caller (Executor) is responsible for checking if progress display is enabled
    mock_io = StringIO.new

    context.setup_output_capture(mock_io)

    # Capture should be set up regardless of TTY status
    assert_instance_of Taski::Execution::TaskOutputRouter, context.output_capture
  end

  def test_teardown_output_capture_when_not_set
    context = Taski::Execution::ExecutionContext.new

    # Should not raise when no capture is set
    context.teardown_output_capture
    assert_nil context.output_capture
  end

  def test_output_capture_active
    context = Taski::Execution::ExecutionContext.new
    mock_io = StringIO.new

    original_stdout = $stdout
    begin
      refute context.output_capture_active?, "Should be inactive before setup"

      context.setup_output_capture(mock_io)
      assert context.output_capture_active?, "Should be active after setup"

      context.teardown_output_capture
      refute context.output_capture_active?, "Should be inactive after teardown"
    ensure
      $stdout = original_stdout
    end
  end

  # ========================================
  # Clean Lifecycle Notification Tests
  # ========================================

  def test_notify_clean_started
    context = Taski::Execution::ExecutionContext.new
    called_with = nil
    observer = Object.new
    observer.define_singleton_method(:update_task) do |task_class, state:, **_kwargs|
      called_with = {task_class: task_class, state: state}
    end

    context.add_observer(observer)
    context.notify_clean_started(String)

    assert_equal({task_class: String, state: :cleaning}, called_with)
  end

  def test_notify_clean_completed_success
    context = Taski::Execution::ExecutionContext.new
    called_with = nil
    observer = Object.new
    observer.define_singleton_method(:update_task) do |task_class, state:, duration:, error:|
      called_with = {task_class: task_class, state: state, duration: duration, error: error}
    end

    context.add_observer(observer)
    context.notify_clean_completed(String, duration: 2.5)

    assert_equal String, called_with[:task_class]
    assert_equal :clean_completed, called_with[:state]
    assert_equal 2.5, called_with[:duration]
    assert_nil called_with[:error]
  end

  def test_notify_clean_completed_with_error
    context = Taski::Execution::ExecutionContext.new
    called_with = nil
    observer = Object.new
    observer.define_singleton_method(:update_task) do |task_class, state:, duration:, error:|
      called_with = {task_class: task_class, state: state, duration: duration, error: error}
    end

    test_error = StandardError.new("clean error")
    context.add_observer(observer)
    context.notify_clean_completed(String, error: test_error)

    assert_equal :clean_failed, called_with[:state]
    assert_equal test_error, called_with[:error]
  end
end
