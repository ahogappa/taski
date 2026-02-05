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

  def test_notify_section_impl_selected
    context = Taski::Execution::ExecutionContext.new
    called_with = nil
    observer = Object.new
    observer.define_singleton_method(:register_section_impl) do |section_class, impl_class|
      called_with = {section_class: section_class, impl_class: impl_class}
    end

    context.add_observer(observer)
    context.notify_section_impl_selected(String, Integer)

    assert_equal({section_class: String, impl_class: Integer}, called_with)
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

    context.execution_trigger = lambda { |task_class, registry|
      triggered_with = {task_class: task_class, registry: registry}
    }

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

  # ========================================
  # Runtime Dependency Tracking Tests
  # ========================================

  def test_register_runtime_dependency
    context = Taski::Execution::ExecutionContext.new

    context.register_runtime_dependency(String, Integer)

    deps = context.runtime_dependencies
    assert_includes deps[String], Integer
  end

  def test_register_multiple_runtime_dependencies
    context = Taski::Execution::ExecutionContext.new

    context.register_runtime_dependency(String, Integer)
    context.register_runtime_dependency(String, Float)
    context.register_runtime_dependency(Array, Hash)

    deps = context.runtime_dependencies
    assert_includes deps[String], Integer
    assert_includes deps[String], Float
    assert_includes deps[Array], Hash
    assert_equal 2, deps[String].size
    assert_equal 1, deps[Array].size
  end

  def test_runtime_dependencies_returns_copy
    context = Taski::Execution::ExecutionContext.new
    context.register_runtime_dependency(String, Integer)

    deps = context.runtime_dependencies
    deps[String].clear
    deps[Array] = Set.new

    # Original should be unchanged
    new_deps = context.runtime_dependencies
    assert_includes new_deps[String], Integer
    refute new_deps.key?(Array)
  end

  def test_runtime_dependencies_thread_safety
    context = Taski::Execution::ExecutionContext.new
    threads = []
    classes = Array.new(10) { Class.new }

    # Spawn multiple threads that register dependencies concurrently
    10.times do |i|
      threads << Thread.new do
        50.times do |j|
          context.register_runtime_dependency(classes[i], classes[(i + j + 1) % 10])
        end
      end
    end

    threads.each(&:join)

    # All dependencies should be registered
    deps = context.runtime_dependencies
    classes.each do |cls|
      assert deps.key?(cls), "Expected #{cls} to have dependencies registered"
    end
  end

  # ========================================
  # Phase 2: Pull API Tests
  # ========================================

  def test_current_phase_defaults_to_nil
    context = Taski::Execution::ExecutionContext.new
    assert_nil context.current_phase
  end

  def test_current_phase_can_be_set_to_run
    context = Taski::Execution::ExecutionContext.new
    context.current_phase = :run
    assert_equal :run, context.current_phase
  end

  def test_current_phase_can_be_set_to_clean
    context = Taski::Execution::ExecutionContext.new
    context.current_phase = :clean
    assert_equal :clean, context.current_phase
  end

  def test_root_task_class_defaults_to_nil
    context = Taski::Execution::ExecutionContext.new
    assert_nil context.root_task_class
  end

  def test_root_task_class_can_be_set
    context = Taski::Execution::ExecutionContext.new
    task_class = Class.new
    context.root_task_class = task_class
    assert_equal task_class, context.root_task_class
  end

  def test_dependency_graph_defaults_to_nil
    context = Taski::Execution::ExecutionContext.new
    assert_nil context.dependency_graph
  end

  def test_dependency_graph_can_be_injected
    context = Taski::Execution::ExecutionContext.new
    # Use a mock object as dependency graph
    mock_graph = Object.new
    context.dependency_graph = mock_graph
    assert_equal mock_graph, context.dependency_graph
  end

  def test_output_stream_returns_output_capture
    context = Taski::Execution::ExecutionContext.new
    # Before output capture is set, output_stream should be nil
    assert_nil context.output_stream

    # After setting up output capture
    output = StringIO.new
    context.setup_output_capture(output)
    refute_nil context.output_stream
    assert_kind_of Taski::Execution::TaskOutputRouter, context.output_stream

    context.teardown_output_capture
  end

  # === output_stream.read API tests ===

  def test_output_stream_read_returns_all_lines_by_default
    context = Taski::Execution::ExecutionContext.new
    output = StringIO.new
    context.setup_output_capture(output)

    task_class = Class.new
    output_router = context.output_stream
    output_router.start_capture(task_class)

    # Simulate output capture by writing directly to recent_lines
    output_router.instance_variable_get(:@recent_lines)[task_class] = %w[line1 line2 line3]

    # Read without limit should return all lines
    result = output_router.read(task_class)
    assert_equal %w[line1 line2 line3], result

    output_router.stop_capture
    context.teardown_output_capture
  end

  def test_output_stream_read_respects_limit
    context = Taski::Execution::ExecutionContext.new
    output = StringIO.new
    context.setup_output_capture(output)

    task_class = Class.new
    output_router = context.output_stream
    output_router.start_capture(task_class)

    # Simulate output capture
    output_router.instance_variable_get(:@recent_lines)[task_class] = %w[line1 line2 line3 line4 line5]

    # Read with limit should return only the last N lines
    result = output_router.read(task_class, limit: 2)
    assert_equal %w[line4 line5], result

    output_router.stop_capture
    context.teardown_output_capture
  end

  def test_output_stream_read_returns_empty_array_for_unknown_task
    context = Taski::Execution::ExecutionContext.new
    output = StringIO.new
    context.setup_output_capture(output)

    unknown_task = Class.new
    result = context.output_stream.read(unknown_task)
    assert_equal [], result

    context.teardown_output_capture
  end
end
