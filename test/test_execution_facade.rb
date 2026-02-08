# frozen_string_literal: true

require "test_helper"

class TestExecutionFacade < Minitest::Test
  def setup
    Taski::Task.reset! if defined?(Taski::Task)
  end

  # ========================================
  # Constructor and Pull API
  # ========================================

  def test_constructor_stores_root_task_class
    facade = Taski::Execution::ExecutionFacade.new(root_task_class: String)
    assert_equal String, facade.root_task_class
  end

  def test_constructor_stores_dependency_graph
    graph = Taski::StaticAnalysis::DependencyGraph.new
    facade = Taski::Execution::ExecutionFacade.new(root_task_class: String, dependency_graph: graph)
    assert_equal graph, facade.dependency_graph
  end

  def test_dependency_graph_frozen_after_construction
    graph = Taski::StaticAnalysis::DependencyGraph.new
    facade = Taski::Execution::ExecutionFacade.new(root_task_class: String, dependency_graph: graph)
    assert facade.dependency_graph.frozen?, "DependencyGraph should be frozen"
  end

  def test_dependency_graph_nil_when_not_provided
    facade = Taski::Execution::ExecutionFacade.new(root_task_class: String)
    assert_nil facade.dependency_graph
  end

  def test_output_stream_returns_provided_value
    stream = Object.new
    facade = Taski::Execution::ExecutionFacade.new(root_task_class: String, output_stream: stream)
    assert_equal stream, facade.output_stream
  end

  def test_output_stream_nil_when_not_provided
    facade = Taski::Execution::ExecutionFacade.new(root_task_class: String)
    assert_nil facade.output_stream
  end

  # ========================================
  # Thread-local current context
  # ========================================

  def test_current_context_thread_local
    facade = Taski::Execution::ExecutionFacade.new(root_task_class: String)

    assert_nil Taski::Execution::ExecutionFacade.current

    Taski::Execution::ExecutionFacade.current = facade
    assert_equal facade, Taski::Execution::ExecutionFacade.current

    Taski::Execution::ExecutionFacade.current = nil
    assert_nil Taski::Execution::ExecutionFacade.current
  end

  # ========================================
  # Observer management
  # ========================================

  def test_add_and_remove_observer
    facade = Taski::Execution::ExecutionFacade.new(root_task_class: String)
    observer = Object.new

    facade.add_observer(observer)
    assert_includes facade.observers, observer

    facade.remove_observer(observer)
    refute_includes facade.observers, observer
  end

  def test_observers_returns_copy
    facade = Taski::Execution::ExecutionFacade.new(root_task_class: String)
    observer = Object.new
    facade.add_observer(observer)

    observers_copy = facade.observers
    observers_copy.clear

    # Original should still have the observer
    assert_includes facade.observers, observer
  end

  def test_add_observer_sets_context_on_observer
    facade = Taski::Execution::ExecutionFacade.new(root_task_class: String)
    observer = Object.new
    observer.define_singleton_method(:context=) { |ctx| @context = ctx }
    observer.define_singleton_method(:context) { @context }

    facade.add_observer(observer)

    assert_equal facade, observer.context
  end

  def test_add_observer_skips_context_when_not_supported
    facade = Taski::Execution::ExecutionFacade.new(root_task_class: String)
    observer = Object.new # No context= method

    # Should not raise
    facade.add_observer(observer)
    assert_includes facade.observers, observer
  end

  # ========================================
  # Push API: Event System
  # ========================================

  def test_notify_ready_dispatches_on_ready
    facade = Taski::Execution::ExecutionFacade.new(root_task_class: String)
    called = false
    observer = Object.new
    observer.define_singleton_method(:on_ready) { called = true }

    facade.add_observer(observer)
    facade.notify_ready

    assert called
  end

  def test_notify_start_dispatches_on_start
    facade = Taski::Execution::ExecutionFacade.new(root_task_class: String)
    called = false
    observer = Object.new
    observer.define_singleton_method(:on_start) { called = true }

    facade.add_observer(observer)
    facade.notify_start

    assert called
  end

  def test_notify_stop_dispatches_on_stop
    facade = Taski::Execution::ExecutionFacade.new(root_task_class: String)
    called = false
    observer = Object.new
    observer.define_singleton_method(:on_stop) { called = true }

    facade.add_observer(observer)
    facade.notify_stop

    assert called
  end

  def test_notify_task_updated_with_state_transition
    facade = Taski::Execution::ExecutionFacade.new(root_task_class: String)
    called_with = nil
    observer = Object.new
    observer.define_singleton_method(:on_task_updated) do |task_class, previous_state:, current_state:, phase:, timestamp:|
      called_with = {task_class: task_class, previous_state: previous_state, current_state: current_state, phase: phase, timestamp: timestamp}
    end

    now = Time.now
    facade.add_observer(observer)
    facade.notify_task_updated(String, previous_state: :pending, current_state: :running, phase: :run, timestamp: now)

    assert_equal String, called_with[:task_class]
    assert_equal :pending, called_with[:previous_state]
    assert_equal :running, called_with[:current_state]
    assert_equal :run, called_with[:phase]
    assert_equal now, called_with[:timestamp]
  end

  def test_notify_task_updated_registration
    facade = Taski::Execution::ExecutionFacade.new(root_task_class: String)
    called_with = nil
    observer = Object.new
    observer.define_singleton_method(:on_task_updated) do |task_class, previous_state:, current_state:, **_kwargs|
      called_with = {task_class: task_class, previous_state: previous_state, current_state: current_state}
    end

    facade.add_observer(observer)
    facade.notify_task_updated(String, previous_state: nil, current_state: :pending, phase: :run, timestamp: Time.now)

    assert_equal String, called_with[:task_class]
    assert_nil called_with[:previous_state]
    assert_equal :pending, called_with[:current_state]
  end

  def test_notify_task_updated_completed
    facade = Taski::Execution::ExecutionFacade.new(root_task_class: String)
    called_with = nil
    observer = Object.new
    observer.define_singleton_method(:on_task_updated) do |task_class, previous_state:, current_state:, phase:, timestamp:|
      called_with = {previous_state: previous_state, current_state: current_state, phase: phase}
    end

    facade.add_observer(observer)
    facade.notify_task_updated(String, previous_state: :running, current_state: :completed, phase: :run, timestamp: Time.now)

    assert_equal :running, called_with[:previous_state]
    assert_equal :completed, called_with[:current_state]
    assert_equal :run, called_with[:phase]
  end

  def test_notify_task_updated_failed
    facade = Taski::Execution::ExecutionFacade.new(root_task_class: String)
    called_with = nil
    observer = Object.new
    observer.define_singleton_method(:on_task_updated) do |task_class, previous_state:, current_state:, phase:, timestamp:|
      called_with = {current_state: current_state}
    end

    facade.add_observer(observer)
    facade.notify_task_updated(String, previous_state: :running, current_state: :failed, phase: :run, timestamp: Time.now)

    assert_equal :failed, called_with[:current_state]
  end

  def test_notify_task_updated_skipped
    facade = Taski::Execution::ExecutionFacade.new(root_task_class: String)
    called_with = nil
    observer = Object.new
    observer.define_singleton_method(:on_task_updated) do |task_class, previous_state:, current_state:, phase:, timestamp:|
      called_with = {previous_state: previous_state, current_state: current_state}
    end

    facade.add_observer(observer)
    facade.notify_task_updated(String, previous_state: :pending, current_state: :skipped, phase: :run, timestamp: Time.now)

    assert_equal :pending, called_with[:previous_state]
    assert_equal :skipped, called_with[:current_state]
  end

  def test_notify_task_updated_clean_phase
    facade = Taski::Execution::ExecutionFacade.new(root_task_class: String)
    called_with = nil
    observer = Object.new
    observer.define_singleton_method(:on_task_updated) do |task_class, previous_state:, current_state:, phase:, timestamp:|
      called_with = {phase: phase, current_state: current_state}
    end

    facade.add_observer(observer)
    facade.notify_task_updated(String, previous_state: :pending, current_state: :running, phase: :clean, timestamp: Time.now)

    assert_equal :clean, called_with[:phase]
    assert_equal :running, called_with[:current_state]
  end

  def test_notify_group_started_with_phase_and_timestamp
    facade = Taski::Execution::ExecutionFacade.new(root_task_class: String)
    called_with = nil
    observer = Object.new
    observer.define_singleton_method(:on_group_started) do |task_class, group_name, phase:, timestamp:|
      called_with = {task_class: task_class, group_name: group_name, phase: phase, timestamp: timestamp}
    end

    now = Time.now
    facade.add_observer(observer)
    facade.notify_group_started(String, "setup", phase: :run, timestamp: now)

    assert_equal String, called_with[:task_class]
    assert_equal "setup", called_with[:group_name]
    assert_equal :run, called_with[:phase]
    assert_equal now, called_with[:timestamp]
  end

  def test_notify_group_completed_with_phase_and_timestamp
    facade = Taski::Execution::ExecutionFacade.new(root_task_class: String)
    called_with = nil
    observer = Object.new
    observer.define_singleton_method(:on_group_completed) do |task_class, group_name, phase:, timestamp:|
      called_with = {task_class: task_class, group_name: group_name, phase: phase, timestamp: timestamp}
    end

    now = Time.now
    facade.add_observer(observer)
    facade.notify_group_completed(String, "setup", phase: :run, timestamp: now)

    assert_equal String, called_with[:task_class]
    assert_equal "setup", called_with[:group_name]
    assert_equal :run, called_with[:phase]
    assert_equal now, called_with[:timestamp]
  end

  # Test dispatch handles observer exceptions gracefully
  def test_dispatch_handles_observer_exception
    facade = Taski::Execution::ExecutionFacade.new(root_task_class: String)

    first_called = false
    second_called = false

    first_observer = Object.new
    first_observer.define_singleton_method(:on_ready) do
      first_called = true
      raise "Observer error"
    end

    second_observer = Object.new
    second_observer.define_singleton_method(:on_ready) do
      second_called = true
    end

    facade.add_observer(first_observer)
    facade.add_observer(second_observer)

    # Should not raise, and second observer should still be called
    _out, err = capture_io do
      facade.notify_ready
    end

    assert first_called
    assert second_called
    assert_match(/Observer.*raised error/, err)
  end

  # Test dispatch skips observers that don't respond to method
  def test_dispatch_skips_non_responding_observers
    facade = Taski::Execution::ExecutionFacade.new(root_task_class: String)
    observer = Object.new # No methods defined

    facade.add_observer(observer)

    # Should not raise
    facade.notify_task_updated(String, previous_state: nil, current_state: :pending, phase: :run, timestamp: Time.now)
  end

  # ========================================
  # Execution and Clean Triggers
  # ========================================

  def test_execution_trigger_with_custom_trigger
    facade = Taski::Execution::ExecutionFacade.new(root_task_class: String)
    triggered_with = nil

    facade.execution_trigger = ->(task_class, registry) do
      triggered_with = {task_class: task_class, registry: registry}
    end

    registry = Taski::Execution::Registry.new
    facade.trigger_execution(String, registry: registry)

    assert_equal String, triggered_with[:task_class]
    assert_equal registry, triggered_with[:registry]
  end

  def test_execution_trigger_fallback
    facade = Taski::Execution::ExecutionFacade.new(root_task_class: String)

    task_class = Class.new(Taski::Task) do
      exports :value
      def run
        @value = "fallback_test"
      end
    end

    registry = Taski::Execution::Registry.new
    facade.trigger_execution(task_class, registry: registry)

    wrapper = registry.get_task(task_class)
    assert wrapper.completed?
  end

  # ========================================
  # Output Capture
  # ========================================

  def test_setup_output_capture_with_tty
    facade = Taski::Execution::ExecutionFacade.new(root_task_class: String)

    # Create a mock TTY IO
    mock_io = StringIO.new
    mock_io.define_singleton_method(:tty?) { true }

    original_stdout = $stdout
    begin
      facade.setup_output_capture(mock_io)

      refute_nil facade.output_capture
      assert_kind_of Taski::Execution::TaskOutputRouter, $stdout

      facade.teardown_output_capture
      assert_nil facade.output_capture
    ensure
      $stdout = original_stdout
    end
  end

  def test_setup_output_capture_does_not_dispatch_set_output_capture
    facade = Taski::Execution::ExecutionFacade.new(root_task_class: String)

    set_capture_called = false
    observer = Object.new
    observer.define_singleton_method(:set_output_capture) do |_capture|
      set_capture_called = true
    end
    facade.add_observer(observer)

    mock_io = StringIO.new
    original_stdout = $stdout
    begin
      facade.setup_output_capture(mock_io)
      refute set_capture_called, "setup_output_capture should NOT dispatch set_output_capture"
    ensure
      facade.teardown_output_capture
      $stdout = original_stdout
    end
  end

  def test_setup_output_capture_always_sets_capture
    facade = Taski::Execution::ExecutionFacade.new(root_task_class: String)

    mock_io = StringIO.new

    original_stdout = $stdout
    begin
      facade.setup_output_capture(mock_io)

      # Capture should be set up regardless of TTY status
      assert_instance_of Taski::Execution::TaskOutputRouter, facade.output_capture
    ensure
      facade.teardown_output_capture
      $stdout = original_stdout
    end
  end

  def test_setup_output_capture_replaces_stderr
    facade = Taski::Execution::ExecutionFacade.new(root_task_class: String)
    mock_io = StringIO.new

    original_stdout = $stdout
    original_stderr = $stderr
    begin
      facade.setup_output_capture(mock_io)

      assert_kind_of Taski::Execution::TaskOutputRouter, $stderr,
        "$stderr should be replaced with TaskOutputRouter"
      assert_equal $stdout, $stderr,
        "$stdout and $stderr should be the same TaskOutputRouter"
    ensure
      facade.teardown_output_capture
      $stdout = original_stdout
      $stderr = original_stderr
    end
  end

  def test_teardown_output_capture_restores_stderr
    facade = Taski::Execution::ExecutionFacade.new(root_task_class: String)
    mock_io = StringIO.new

    original_stdout = $stdout
    original_stderr = $stderr
    begin
      facade.setup_output_capture(mock_io)
      facade.teardown_output_capture

      assert_equal original_stderr, $stderr,
        "$stderr should be restored to original"
    ensure
      $stdout = original_stdout
      $stderr = original_stderr
    end
  end

  def test_original_stderr_accessor
    facade = Taski::Execution::ExecutionFacade.new(root_task_class: String)
    mock_io = StringIO.new

    original_stdout = $stdout
    original_stderr = $stderr
    begin
      assert_nil facade.original_stderr, "Should be nil before setup"

      facade.setup_output_capture(mock_io)
      assert_equal original_stderr, facade.original_stderr,
        "Should return original stderr during capture"

      facade.teardown_output_capture
      assert_nil facade.original_stderr, "Should be nil after teardown"
    ensure
      $stdout = original_stdout
      $stderr = original_stderr
    end
  end

  # ========================================
  # Stateless Facade
  # ========================================

  def test_facade_holds_no_mutable_domain_state
    facade = Taski::Execution::ExecutionFacade.new(root_task_class: String)

    # Facade stores only configuration — no task states, results, or errors
    refute_respond_to facade, :task_states
    refute_respond_to facade, :results
    refute_respond_to facade, :errors
    refute_respond_to facade, :current_phase
  end

  def test_facade_does_not_track_current_phase
    facade = Taski::Execution::ExecutionFacade.new(root_task_class: String)

    # Phase is not tracked as state in facade
    refute_respond_to facade, :current_phase
    refute_respond_to facade, :phase
  end

  def test_facade_root_task_class_immutable_after_construction
    facade = Taski::Execution::ExecutionFacade.new(root_task_class: String)

    refute_respond_to facade, :root_task_class=
    assert_equal String, facade.root_task_class
  end

  def test_dependency_graph_set_once_then_frozen
    facade = Taski::Execution::ExecutionFacade.new(root_task_class: String)
    graph = Taski::StaticAnalysis::DependencyGraph.new

    facade.update_dependency_graph(graph)
    assert facade.dependency_graph.frozen?

    # Second call is ignored
    graph2 = Taski::StaticAnalysis::DependencyGraph.new
    facade.update_dependency_graph(graph2)
    assert_equal graph, facade.dependency_graph
  end

  # ========================================
  # Thread-local Isolation
  # ========================================

  def test_current_context_isolated_across_threads
    facade1 = Taski::Execution::ExecutionFacade.new(root_task_class: String)
    facade2 = Taski::Execution::ExecutionFacade.new(root_task_class: Integer)

    Taski::Execution::ExecutionFacade.current = facade1

    other_thread_context = nil
    thread = Thread.new do
      Taski::Execution::ExecutionFacade.current = facade2
      other_thread_context = Taski::Execution::ExecutionFacade.current
    end
    thread.join

    # Each thread has its own context
    assert_equal facade1, Taski::Execution::ExecutionFacade.current
    assert_equal facade2, other_thread_context

    Taski::Execution::ExecutionFacade.current = nil
  end

  # ========================================
  # Pull API: dependency_graph
  # ========================================

  def test_dependency_graph_provides_task_relationships
    leaf = Class.new(Taski::Task) do
      exports :value
      def run = @value = "leaf"
    end
    leaf.define_singleton_method(:cached_dependencies) { Set.new }

    root = Class.new(Taski::Task) do
      exports :value
    end
    root.define_singleton_method(:cached_dependencies) { Set[leaf] }

    graph = Taski::StaticAnalysis::DependencyGraph.new.build_from_cached(root)
    facade = Taski::Execution::ExecutionFacade.new(root_task_class: root, dependency_graph: graph)

    deps = facade.dependency_graph.dependencies_for(root)
    assert_includes deps, leaf

    leaf_deps = facade.dependency_graph.dependencies_for(leaf)
    assert_empty leaf_deps
  end

  def test_dependency_graph_all_tasks_returns_full_graph
    leaf = Class.new(Taski::Task) do
      exports :value
      def run = @value = "leaf"
    end
    leaf.define_singleton_method(:cached_dependencies) { Set.new }

    root = Class.new(Taski::Task) do
      exports :value
    end
    root.define_singleton_method(:cached_dependencies) { Set[leaf] }

    graph = Taski::StaticAnalysis::DependencyGraph.new.build_from_cached(root)
    facade = Taski::Execution::ExecutionFacade.new(root_task_class: root, dependency_graph: graph)

    all = facade.dependency_graph.all_tasks
    assert_includes all, root
    assert_includes all, leaf
    assert_equal 2, all.size
  end

  def test_dependency_graph_tree_traversal_multi_level
    # 3-level graph: root -> middle -> leaf
    # Verifies that dependency_graph supports recursive traversal of the tree
    leaf = Class.new(Taski::Task) do
      exports :value
      def run = @value = "leaf"
    end
    leaf.define_singleton_method(:cached_dependencies) { Set.new }

    middle = Class.new(Taski::Task) do
      exports :value
    end
    middle.define_singleton_method(:cached_dependencies) { Set[leaf] }

    root = Class.new(Taski::Task) do
      exports :value
    end
    root.define_singleton_method(:cached_dependencies) { Set[middle] }

    graph = Taski::StaticAnalysis::DependencyGraph.new.build_from_cached(root)
    facade = Taski::Execution::ExecutionFacade.new(root_task_class: root, dependency_graph: graph)

    # Root's children include middle
    root_deps = facade.dependency_graph.dependencies_for(root)
    assert_includes root_deps, middle
    refute_includes root_deps, leaf

    # Middle's children include leaf
    middle_deps = facade.dependency_graph.dependencies_for(middle)
    assert_includes middle_deps, leaf

    # Leaf has no children
    assert_empty facade.dependency_graph.dependencies_for(leaf)

    # Full graph contains all 3 tasks
    assert_equal 3, facade.dependency_graph.all_tasks.size
  end

  # ========================================
  # Pull API: output_stream.read
  # ========================================

  def test_output_stream_read_returns_captured_output
    facade = Taski::Execution::ExecutionFacade.new(root_task_class: String)
    mock_io = StringIO.new
    task_class = Class.new(Taski::Task)

    original_stdout = $stdout
    original_stderr = $stderr
    begin
      facade.setup_output_capture(mock_io)
      capture = facade.output_capture

      # Simulate output capture
      capture.start_capture(task_class)
      capture.send(:store_output_lines, task_class, "captured line\n")
      capture.stop_capture

      lines = capture.read(task_class)
      assert_includes lines, "captured line"
    ensure
      facade.teardown_output_capture
      $stdout = original_stdout
      $stderr = original_stderr
    end
  end

  def test_output_stream_read_with_limit
    facade = Taski::Execution::ExecutionFacade.new(root_task_class: String)
    mock_io = StringIO.new
    task_class = Class.new(Taski::Task)

    original_stdout = $stdout
    original_stderr = $stderr
    begin
      facade.setup_output_capture(mock_io)
      capture = facade.output_capture

      capture.start_capture(task_class)
      data = (1..10).map { |i| "line#{i}" }.join("\n") + "\n"
      capture.send(:store_output_lines, task_class, data)
      capture.stop_capture

      lines = capture.read(task_class, limit: 3)
      assert_equal 3, lines.size
      assert_equal "line10", lines.last
    ensure
      facade.teardown_output_capture
      $stdout = original_stdout
      $stderr = original_stderr
    end
  end

  def test_teardown_output_capture_when_not_set
    facade = Taski::Execution::ExecutionFacade.new(root_task_class: String)

    # Should not raise when no capture is set
    facade.teardown_output_capture
    assert_nil facade.output_capture
  end

  def test_output_capture_active
    facade = Taski::Execution::ExecutionFacade.new(root_task_class: String)
    mock_io = StringIO.new

    original_stdout = $stdout
    begin
      refute facade.output_capture_active?, "Should be inactive before setup"

      facade.setup_output_capture(mock_io)
      assert facade.output_capture_active?, "Should be active after setup"

      facade.teardown_output_capture
      refute facade.output_capture_active?, "Should be inactive after teardown"
    ensure
      $stdout = original_stdout
    end
  end
end
