# frozen_string_literal: true

require "test_helper"
require "stringio"
require "taski/progress/layout/tree"
require "taski/progress/theme/default"

# Mock dependency graph that builds from task's cached_dependencies
class MockDependencyGraph
  def initialize(root_task)
    @root_task = root_task
    @graph = {}
    build_graph(root_task)
  end

  def dependencies_for(task_class)
    @graph[task_class] || []
  end

  private

  def build_graph(task_class, visited = Set.new)
    return if visited.include?(task_class)

    visited.add(task_class)
    deps = task_class.respond_to?(:cached_dependencies) ? task_class.cached_dependencies : []
    @graph[task_class] = deps
    deps.each { |dep| build_graph(dep, visited) }
  end
end

# Mock facade for testing
class MockFacade
  attr_reader :dependency_graph
  attr_accessor :root_task_class

  def initialize(dependency_graph, root_task_class = nil)
    @dependency_graph = dependency_graph
    @root_task_class = root_task_class
  end

  def current_phase
    :run
  end
end

class TestLayoutTree < Minitest::Test
  include LayoutTestHelper

  def setup
    @output = StringIO.new
    @layout = Taski::Progress::Layout::Tree.new(output: @output)
  end

  def test_can_initialize_with_default_template
    layout = Taski::Progress::Layout::Tree.new(output: @output)
    assert_instance_of Taski::Progress::Layout::Tree, layout
  end

  def test_can_initialize_with_custom_theme
    template = Taski::Progress::Theme::Default.new
    layout = Taski::Progress::Layout::Tree.new(output: @output, theme: template)
    assert_instance_of Taski::Progress::Layout::Tree, layout
  end

  def test_inherits_from_layout_base
    assert_kind_of Taski::Progress::Layout::Base, @layout
  end

  def test_registers_root_task_on_ready
    root_task = stub_task_class("RootTask")
    setup_layout_with_graph(root_task)
    assert @layout.task_registered?(root_task)
  end

  private

  def setup_layout_with_graph(root_task)
    graph = MockDependencyGraph.new(root_task)
    facade = MockFacade.new(graph, root_task)
    @layout.facade = facade
    @layout.send(:on_ready)
  end

  def test_tracks_task_state
    task_class = stub_task_class("MyTask")
    @layout.register_task(task_class)
    simulate_task_start(@layout, task_class)
    assert_equal :running, @layout.task_state(task_class)
  end

  def test_tracks_completed_task
    task_class = stub_task_class("MyTask")
    @layout.register_task(task_class)
    simulate_task_start(@layout, task_class)
    simulate_task_complete(@layout, task_class)
    assert_equal :completed, @layout.task_state(task_class)
  end

  private

  def stub_task_class(name)
    klass = Class.new
    klass.define_singleton_method(:name) { name }
    klass.define_singleton_method(:cached_dependencies) { [] }
    klass.define_singleton_method(:section?) { false }
    klass
  end
end

class TestLayoutTreeRendering < Minitest::Test
  include LayoutTestHelper

  def setup
    @output = StringIO.new
    @layout = Taski::Progress::Layout::Tree.new(output: @output)
  end

  # Test that Layout::Tree uses Theme::Detail by default with icons/spinner

  def test_outputs_task_start_with_spinner
    task_class = stub_task_class("MyTask")
    @layout.register_task(task_class)
    @layout.start
    simulate_task_start(@layout, task_class)
    @layout.stop

    # Theme::Detail uses spinner for running tasks
    assert_includes @output.string, "⠋ MyTask"
  end

  def test_outputs_task_success_with_icon_and_duration
    task_class = stub_task_class("MyTask")
    @layout.register_task(task_class)
    @layout.start
    start_time = Time.now
    simulate_task_start(@layout, task_class, timestamp: start_time)
    simulate_task_complete(@layout, task_class, timestamp: start_time + 0.123)
    @layout.stop

    # Theme::Detail uses ✓ icon for completed tasks
    assert_includes @output.string, "✓"
    assert_includes @output.string, "MyTask"
    assert_match(/\(\d+(\.\d+)?ms\)/, @output.string)
  end

  def test_outputs_task_fail_with_icon
    task_class = stub_task_class("MyTask")
    @layout.register_task(task_class)
    @layout.start
    simulate_task_start(@layout, task_class)
    simulate_task_fail(@layout, task_class)
    @layout.stop

    # Theme::Detail uses ✗ icon for failed tasks
    # Note: error message is not shown via notification - exceptions propagate to top level
    assert_includes @output.string, "✗"
    assert_includes @output.string, "MyTask"
  end

  def test_outputs_execution_start
    task_class = stub_task_class("RootTask")
    @layout.set_root_task(task_class)
    @layout.start
    @layout.stop

    assert_includes @output.string, "[TASKI] Starting RootTask"
  end

  def test_outputs_execution_complete
    task_class = stub_task_class("RootTask")
    @layout.set_root_task(task_class)
    @layout.register_task(task_class)
    @layout.start
    simulate_task_start(@layout, task_class)
    simulate_task_complete(@layout, task_class)
    @layout.stop

    assert_includes @output.string, "[TASKI] Completed: 1/1 tasks"
  end

  def test_outputs_execution_fail
    task_class = stub_task_class("RootTask")
    @layout.set_root_task(task_class)
    @layout.register_task(task_class)
    @layout.start
    simulate_task_start(@layout, task_class)
    simulate_task_fail(@layout, task_class)
    @layout.stop

    assert_includes @output.string, "[TASKI] Failed: 1/1 tasks"
  end

  private

  def stub_task_class(name)
    klass = Class.new
    klass.define_singleton_method(:name) { name }
    klass.define_singleton_method(:cached_dependencies) { [] }
    klass.define_singleton_method(:section?) { false }
    klass
  end
end

class TestLayoutTreePrefix < Minitest::Test
  include LayoutTestHelper

  def setup
    @output = StringIO.new
    @layout = Taski::Progress::Layout::Tree.new(output: @output)
  end

  def test_tree_prefix_for_single_child
    # Create a parent with one child
    child = stub_task_class("ChildTask")
    parent = stub_task_class_with_deps("ParentTask", [child])

    setup_layout_with_graph(parent)
    @layout.start
    simulate_task_start(@layout, child)
    @layout.stop

    # Child should have tree prefix with spinner
    output = @output.string
    assert_includes output, "└── ⠋ ChildTask"
  end

  def test_tree_prefix_for_multiple_children
    # Create a parent with two children
    child1 = stub_task_class("Child1")
    child2 = stub_task_class("Child2")
    parent = stub_task_class_with_deps("ParentTask", [child1, child2])

    setup_layout_with_graph(parent)
    @layout.start
    simulate_task_start(@layout, child1)
    simulate_task_start(@layout, child2)
    @layout.stop

    output = @output.string
    # First child should use branch with spinner
    assert_includes output, "├── ⠋ Child1"
    # Last child should use last_branch with spinner
    assert_includes output, "└── ⠋ Child2"
  end

  def test_tree_prefix_for_nested_children
    # Create a grandchild -> child -> parent structure
    grandchild = stub_task_class("GrandChild")
    child = stub_task_class_with_deps("ChildTask", [grandchild])
    parent = stub_task_class_with_deps("ParentTask", [child])

    setup_layout_with_graph(parent)
    @layout.start
    simulate_task_start(@layout, child)
    simulate_task_start(@layout, grandchild)
    @layout.stop

    output = @output.string
    # Child at depth 1 with spinner
    assert_includes output, "└── ⠋ ChildTask"
    # Grandchild at depth 2 with proper indentation and spinner
    assert_includes output, "    └── ⠋ GrandChild"
  end

  def test_tree_prefix_with_continuation_line
    # Create parent with two children, first child has a grandchild
    grandchild = stub_task_class("GrandChild")
    child1 = stub_task_class_with_deps("Child1", [grandchild])
    child2 = stub_task_class("Child2")
    parent = stub_task_class_with_deps("ParentTask", [child1, child2])

    setup_layout_with_graph(parent)
    @layout.start
    simulate_task_start(@layout, child1)
    simulate_task_start(@layout, grandchild)
    simulate_task_start(@layout, child2)
    @layout.stop

    output = @output.string
    # Child1 is not last (has sibling child2) with spinner
    assert_includes output, "├── ⠋ Child1"
    # Grandchild should have vertical continuation line with spinner
    assert_includes output, "│   └── ⠋ GrandChild"
    # Child2 is last with spinner
    assert_includes output, "└── ⠋ Child2"
  end

  def test_root_task_has_no_prefix
    root = stub_task_class("RootTask")
    setup_layout_with_graph(root)
    @layout.start
    simulate_task_start(@layout, root)
    @layout.stop

    output = @output.string
    # Root task should NOT have tree prefix, but should have spinner
    assert_includes output, "⠋ RootTask"
    # But should not have the prefix before it
    refute_includes output, "├── ⠋ RootTask"
    refute_includes output, "└── ⠋ RootTask"
  end

  private

  def setup_layout_with_graph(root_task)
    graph = MockDependencyGraph.new(root_task)
    facade = MockFacade.new(graph, root_task)
    @layout.facade = facade
    @layout.send(:on_ready)
  end

  def stub_task_class(name)
    klass = Class.new
    klass.define_singleton_method(:name) { name }
    klass.define_singleton_method(:cached_dependencies) { [] }
    klass.define_singleton_method(:section?) { false }
    klass
  end

  def stub_task_class_with_deps(name, deps)
    klass = Class.new
    klass.define_singleton_method(:name) { name }
    klass.define_singleton_method(:cached_dependencies) { deps }
    klass.define_singleton_method(:section?) { false }
    klass
  end
end

class TestLayoutTreeTaskContent < Minitest::Test
  include LayoutTestHelper

  def setup
    @output = StringIO.new
    @layout = Taski::Progress::Layout::Tree.new(output: @output)
  end

  def test_build_task_content_uses_icon_for_pending_state
    task_class = stub_task_class("MyTask")
    @layout.register_task(task_class)

    content = @layout.send(:build_task_content, task_class)
    # Theme::Detail uses ○ icon for pending
    assert_includes content, "○"
    assert_includes content, "MyTask"
  end

  def test_build_task_content_uses_spinner_for_running_state
    task_class = stub_task_class("MyTask")
    @layout.register_task(task_class)
    simulate_task_start(@layout, task_class)

    content = @layout.send(:build_task_content, task_class)
    # Theme::Detail uses spinner for running
    assert_includes content, "⠋"
    assert_includes content, "MyTask"
  end

  def test_build_task_content_uses_icon_for_completed_state
    task_class = stub_task_class("MyTask")
    @layout.register_task(task_class)
    start_time = Time.now
    simulate_task_start(@layout, task_class, timestamp: start_time)
    simulate_task_complete(@layout, task_class, timestamp: start_time + 0.1)

    content = @layout.send(:build_task_content, task_class)
    # Theme::Detail uses ✓ icon for completed
    assert_includes content, "✓"
    assert_includes content, "MyTask"
    assert_match(/\(\d+(\.\d+)?ms\)/, content)
  end

  def test_build_task_content_uses_icon_for_failed_state
    task_class = stub_task_class("MyTask")
    @layout.register_task(task_class)
    simulate_task_start(@layout, task_class)
    simulate_task_fail(@layout, task_class)

    content = @layout.send(:build_task_content, task_class)
    # Theme::Detail uses ✗ icon for failed
    # Note: error message is NOT shown via notification - exceptions propagate to top level (Plan design)
    assert_includes content, "✗"
    assert_includes content, "MyTask"
  end

  def test_build_task_content_uses_icon_for_skipped_state
    task_class = stub_task_class("SkippedTask")
    @layout.register_task(task_class)
    simulate_task_skip(@layout, task_class)

    content = @layout.send(:build_task_content, task_class)
    # Theme::Detail uses ⊘ icon for skipped
    assert_includes content, "⊘"
    assert_includes content, "SkippedTask"
  end

  private

  def stub_task_class(name)
    klass = Class.new
    klass.define_singleton_method(:name) { name }
    klass.define_singleton_method(:cached_dependencies) { [] }
    klass.define_singleton_method(:section?) { false }
    klass
  end
end

class TestLayoutTreeWithCustomTemplate < Minitest::Test
  include LayoutTestHelper

  def setup
    @output = StringIO.new
  end

  def test_uses_custom_theme_task_start
    custom_theme = Class.new(Taski::Progress::Theme::Base) do
      def task_start
        "[BEGIN] {{ task.name }}"
      end
    end.new

    layout = Taski::Progress::Layout::Tree.new(output: @output, theme: custom_theme)
    task_class = stub_task_class("MyTask")
    layout.register_task(task_class)
    layout.start
    simulate_task_start(layout, task_class)
    layout.stop

    assert_includes @output.string, "[BEGIN] MyTask"
  end

  def test_uses_custom_theme_task_success
    custom_theme = Class.new(Taski::Progress::Theme::Base) do
      def task_success
        "[OK] {{ task.name }}"
      end
    end.new

    layout = Taski::Progress::Layout::Tree.new(output: @output, theme: custom_theme)
    task_class = stub_task_class("MyTask")
    layout.register_task(task_class)
    layout.start
    simulate_task_start(layout, task_class)
    simulate_task_complete(layout, task_class)
    layout.stop

    assert_includes @output.string, "[OK] MyTask"
  end

  def test_tree_prefix_with_custom_theme
    custom_theme = Class.new(Taski::Progress::Theme::Base) do
      def task_start
        "=> {{ task.name }}"
      end
    end.new

    layout = Taski::Progress::Layout::Tree.new(output: @output, theme: custom_theme)

    child = stub_task_class("ChildTask")
    parent = stub_task_class_with_deps("ParentTask", [child])

    # Setup with graph
    graph = MockDependencyGraph.new(parent)
    facade = MockFacade.new(graph, parent)
    layout.facade = facade
    layout.send(:on_ready)

    layout.start
    simulate_task_start(layout, child)
    layout.stop

    # Tree prefix should combine with custom template
    assert_includes @output.string, "└── => ChildTask"
  end

  private

  def stub_task_class(name)
    klass = Class.new
    klass.define_singleton_method(:name) { name }
    klass.define_singleton_method(:cached_dependencies) { [] }
    klass.define_singleton_method(:section?) { false }
    klass
  end

  def stub_task_class_with_deps(name, deps)
    klass = Class.new
    klass.define_singleton_method(:name) { name }
    klass.define_singleton_method(:cached_dependencies) { deps }
    klass.define_singleton_method(:section?) { false }
    klass
  end
end

class TestLayoutTreeOnReady < Minitest::Test
  def setup
    @output = StringIO.new
    @layout = Taski::Progress::Layout::Tree.new(output: @output)
    @context = Taski::Execution::ExecutionContext.new
    @context.add_observer(@layout)
  end

  def test_on_ready_stores_dependency_graph_from_facade
    # Create a mock dependency graph with dependencies_for method
    mock_graph = Object.new
    mock_graph.define_singleton_method(:dependencies_for) { |_| [] }
    @context.dependency_graph = mock_graph

    # Set root task on context
    root_task = stub_task_class("RootTask")
    @context.root_task_class = root_task

    # Call on_ready via send (protected method)
    @layout.send(:on_ready)

    # Verify layout has access to the stored graph
    assert_equal mock_graph, @layout.instance_variable_get(:@dependency_graph)
  end

  def test_on_ready_works_without_dependency_graph
    # Context without dependency_graph set
    root_task = stub_task_class("RootTask")
    @context.root_task_class = root_task

    # Should not raise
    @layout.send(:on_ready)

    # Graph should be nil
    assert_nil @layout.instance_variable_get(:@dependency_graph)
  end

  def test_build_tree_from_graph_uses_dependency_graph
    # Create tasks
    child_task = stub_task_class("ChildTask")
    parent_task = stub_task_class("ParentTask")

    # Create a mock dependency graph that returns specific dependencies
    mock_graph = Object.new
    mock_graph.define_singleton_method(:dependencies_for) do |task_class|
      if task_class.name == "ParentTask"
        Set.new([child_task])
      else
        Set.new
      end
    end
    @context.dependency_graph = mock_graph

    # Call on_ready to store the graph
    @layout.send(:on_ready)

    # build_tree_from_graph should use the cached graph
    tree = @layout.send(:build_tree_from_graph, parent_task)
    assert_equal parent_task, tree[:task_class]
    assert_equal 1, tree[:children].size
    assert_equal child_task, tree[:children].first[:task_class]
  end

  private

  def stub_task_class(name)
    klass = Class.new
    klass.define_singleton_method(:name) { name }
    klass.define_singleton_method(:cached_dependencies) { [] }
    klass.define_singleton_method(:section?) { false }
    klass
  end
end
