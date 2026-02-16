# frozen_string_literal: true

require "test_helper"
require "stringio"
require "taski/progress/layout/tree"
require "taski/progress/theme/default"
require "taski/progress/theme/plain"

class TestLayoutTreeFactory < Minitest::Test
  def test_for_returns_live_for_tty_output
    output = StringIO.new
    output.define_singleton_method(:tty?) { true }
    layout = Taski::Progress::Layout::Tree.for(output: output)
    assert_instance_of Taski::Progress::Layout::Tree::Live, layout
  end

  def test_for_returns_event_for_non_tty_output
    output = StringIO.new
    layout = Taski::Progress::Layout::Tree.for(output: output)
    assert_instance_of Taski::Progress::Layout::Tree::Event, layout
  end

  def test_for_passes_theme_to_live
    output = StringIO.new
    output.define_singleton_method(:tty?) { true }
    theme = Taski::Progress::Theme::Plain.new
    layout = Taski::Progress::Layout::Tree.for(output: output, theme: theme)
    assert_instance_of Taski::Progress::Layout::Tree::Live, layout
  end

  def test_for_passes_theme_to_event
    output = StringIO.new
    theme = Taski::Progress::Theme::Plain.new
    layout = Taski::Progress::Layout::Tree.for(output: output, theme: theme)
    assert_instance_of Taski::Progress::Layout::Tree::Event, layout
  end
end

class TestLayoutTreeEvent < Minitest::Test
  include TaskiTestHelper

  def setup
    @output = StringIO.new
    @layout = Taski::Progress::Layout::Tree::Event.new(output: @output)
  end

  def test_inherits_from_layout_base
    assert_kind_of Taski::Progress::Layout::Base, @layout
  end

  def test_includes_tree_structure
    assert_kind_of Taski::Progress::Layout::Tree::Structure, @layout
  end

  def test_can_initialize_with_default_theme
    layout = Taski::Progress::Layout::Tree::Event.new(output: @output)
    assert_instance_of Taski::Progress::Layout::Tree::Event, layout
  end

  def test_can_initialize_with_custom_theme
    theme = Taski::Progress::Theme::Default.new
    layout = Taski::Progress::Layout::Tree::Event.new(output: @output, theme: theme)
    assert_instance_of Taski::Progress::Layout::Tree::Event, layout
  end

  def test_registers_root_task_on_ready
    root_task = stub_task_class("RootTask")
    ctx = mock_execution_facade(root_task_class: root_task)
    @layout.context = ctx
    @layout.on_ready
    assert @layout.task_registered?(root_task)
  end

  def test_tracks_task_state
    task_class = stub_task_class("MyTask")
    @layout.on_task_updated(task_class, previous_state: nil, current_state: :pending, phase: :run, timestamp: Time.now)
    @layout.on_task_updated(task_class, previous_state: :pending, current_state: :running, phase: :run, timestamp: Time.now)
    assert_equal :running, @layout.task_state(task_class)
  end

  def test_tracks_completed_task
    task_class = stub_task_class("MyTask")
    started_at = Time.now
    @layout.on_task_updated(task_class, previous_state: nil, current_state: :pending, phase: :run, timestamp: started_at)
    @layout.on_task_updated(task_class, previous_state: :pending, current_state: :running, phase: :run, timestamp: started_at)
    @layout.on_task_updated(task_class, previous_state: :running, current_state: :completed, phase: :run, timestamp: started_at + 0.1)
    assert_equal :completed, @layout.task_state(task_class)
  end

  private

  def stub_task_class(name)
    klass = Class.new
    klass.define_singleton_method(:name) { name }
    klass.define_singleton_method(:cached_dependencies) { [] }
    klass
  end
end

class TestLayoutTreeEventRendering < Minitest::Test
  include TaskiTestHelper

  def setup
    @output = StringIO.new
    @layout = Taski::Progress::Layout::Tree::Event.new(output: @output)
  end

  def test_outputs_task_start_with_spinner
    task_class = stub_task_class("MyTask")
    @layout.on_task_updated(task_class, previous_state: nil, current_state: :pending, phase: :run, timestamp: Time.now)
    @layout.on_start
    @layout.on_task_updated(task_class, previous_state: :pending, current_state: :running, phase: :run, timestamp: Time.now)
    @layout.on_stop

    assert_includes @output.string, "⠋ MyTask"
  end

  def test_outputs_task_success_with_icon_and_duration
    task_class = stub_task_class("MyTask")
    started_at = Time.now
    @layout.on_task_updated(task_class, previous_state: nil, current_state: :pending, phase: :run, timestamp: started_at)
    @layout.on_start
    @layout.on_task_updated(task_class, previous_state: :pending, current_state: :running, phase: :run, timestamp: started_at)
    @layout.on_task_updated(task_class, previous_state: :running, current_state: :completed, phase: :run, timestamp: started_at + 0.123)
    @layout.on_stop

    assert_includes @output.string, "✓"
    assert_includes @output.string, "MyTask"
    assert_includes @output.string, "(123"
  end

  def test_outputs_task_fail_with_icon
    task_class = stub_task_class("MyTask")
    started_at = Time.now
    @layout.on_task_updated(task_class, previous_state: nil, current_state: :pending, phase: :run, timestamp: started_at)
    @layout.on_start
    @layout.on_task_updated(task_class, previous_state: :pending, current_state: :running, phase: :run, timestamp: started_at)
    @layout.on_task_updated(task_class, previous_state: :running, current_state: :failed, phase: :run, timestamp: started_at + 0.001)
    @layout.on_stop

    assert_includes @output.string, "✗"
    assert_includes @output.string, "MyTask"
  end

  def test_outputs_execution_start
    task_class = stub_task_class("RootTask")
    ctx = mock_execution_facade(root_task_class: task_class)
    @layout.context = ctx
    @layout.on_ready
    @layout.on_start
    @layout.on_stop

    assert_includes @output.string, "[TASKI] Starting RootTask"
  end

  def test_outputs_execution_complete
    task_class = stub_task_class("RootTask")
    ctx = mock_execution_facade(root_task_class: task_class)
    @layout.context = ctx
    @layout.on_ready
    started_at = Time.now
    @layout.on_task_updated(task_class, previous_state: nil, current_state: :pending, phase: :run, timestamp: started_at)
    @layout.on_start
    @layout.on_task_updated(task_class, previous_state: :pending, current_state: :running, phase: :run, timestamp: started_at)
    @layout.on_task_updated(task_class, previous_state: :running, current_state: :completed, phase: :run, timestamp: started_at + 0.1)
    @layout.on_stop

    assert_includes @output.string, "[TASKI] Completed: 1/1 tasks"
  end

  def test_outputs_execution_fail
    task_class = stub_task_class("RootTask")
    ctx = mock_execution_facade(root_task_class: task_class)
    @layout.context = ctx
    @layout.on_ready
    started_at = Time.now
    @layout.on_task_updated(task_class, previous_state: nil, current_state: :pending, phase: :run, timestamp: started_at)
    @layout.on_start
    @layout.on_task_updated(task_class, previous_state: :pending, current_state: :running, phase: :run, timestamp: started_at)
    @layout.on_task_updated(task_class, previous_state: :running, current_state: :failed, phase: :run, timestamp: started_at + 0.001)
    @layout.on_stop

    assert_includes @output.string, "[TASKI] Failed: 1/1 tasks"
  end

  private

  def stub_task_class(name)
    klass = Class.new
    klass.define_singleton_method(:name) { name }
    klass.define_singleton_method(:cached_dependencies) { [] }
    klass
  end
end

class TestLayoutTreeEventPrefix < Minitest::Test
  include TaskiTestHelper

  def setup
    @output = StringIO.new
    @layout = Taski::Progress::Layout::Tree::Event.new(output: @output)
  end

  def test_tree_prefix_for_single_child
    child = stub_task_class("ChildTask")
    parent = stub_task_class_with_deps("ParentTask", [child])

    ctx = mock_execution_facade(root_task_class: parent)
    @layout.context = ctx
    @layout.on_ready
    @layout.on_start
    @layout.on_task_updated(child, previous_state: :pending, current_state: :running, phase: :run, timestamp: Time.now)
    @layout.on_stop

    assert_includes @output.string, "└── ⠋ ChildTask"
  end

  def test_tree_prefix_for_multiple_children
    child1 = stub_task_class("Child1")
    child2 = stub_task_class("Child2")
    parent = stub_task_class_with_deps("ParentTask", [child1, child2])

    ctx = mock_execution_facade(root_task_class: parent)
    @layout.context = ctx
    @layout.on_ready
    @layout.on_start
    @layout.on_task_updated(child1, previous_state: :pending, current_state: :running, phase: :run, timestamp: Time.now)
    @layout.on_task_updated(child2, previous_state: :pending, current_state: :running, phase: :run, timestamp: Time.now)
    @layout.on_stop

    assert_includes @output.string, "├── ⠋ Child1"
    assert_includes @output.string, "└── ⠋ Child2"
  end

  def test_tree_prefix_for_nested_children
    grandchild = stub_task_class("GrandChild")
    child = stub_task_class_with_deps("ChildTask", [grandchild])
    parent = stub_task_class_with_deps("ParentTask", [child])

    ctx = mock_execution_facade(root_task_class: parent)
    @layout.context = ctx
    @layout.on_ready
    @layout.on_start
    @layout.on_task_updated(child, previous_state: :pending, current_state: :running, phase: :run, timestamp: Time.now)
    @layout.on_task_updated(grandchild, previous_state: :pending, current_state: :running, phase: :run, timestamp: Time.now)
    @layout.on_stop

    assert_includes @output.string, "└── ⠋ ChildTask"
    assert_includes @output.string, "    └── ⠋ GrandChild"
  end

  def test_tree_prefix_with_continuation_line
    grandchild = stub_task_class("GrandChild")
    child1 = stub_task_class_with_deps("Child1", [grandchild])
    child2 = stub_task_class("Child2")
    parent = stub_task_class_with_deps("ParentTask", [child1, child2])

    ctx = mock_execution_facade(root_task_class: parent)
    @layout.context = ctx
    @layout.on_ready
    @layout.on_start
    @layout.on_task_updated(child1, previous_state: :pending, current_state: :running, phase: :run, timestamp: Time.now)
    @layout.on_task_updated(grandchild, previous_state: :pending, current_state: :running, phase: :run, timestamp: Time.now)
    @layout.on_task_updated(child2, previous_state: :pending, current_state: :running, phase: :run, timestamp: Time.now)
    @layout.on_stop

    assert_includes @output.string, "├── ⠋ Child1"
    assert_includes @output.string, "│   └── ⠋ GrandChild"
    assert_includes @output.string, "└── ⠋ Child2"
  end

  def test_root_task_has_no_prefix
    root = stub_task_class("RootTask")
    ctx = mock_execution_facade(root_task_class: root)
    @layout.context = ctx
    @layout.on_ready
    @layout.on_start
    @layout.on_task_updated(root, previous_state: :pending, current_state: :running, phase: :run, timestamp: Time.now)
    @layout.on_stop

    assert_includes @output.string, "⠋ RootTask"
    refute_includes @output.string, "├── ⠋ RootTask"
    refute_includes @output.string, "└── ⠋ RootTask"
  end

  private

  def stub_task_class(name)
    klass = Class.new
    klass.define_singleton_method(:name) { name }
    klass.define_singleton_method(:cached_dependencies) { [] }
    klass
  end

  def stub_task_class_with_deps(name, deps)
    klass = Class.new
    klass.define_singleton_method(:name) { name }
    klass.define_singleton_method(:cached_dependencies) { deps }
    klass
  end
end

class TestLayoutTreeEventTaskContent < Minitest::Test
  def setup
    @output = StringIO.new
    @layout = Taski::Progress::Layout::Tree::Event.new(output: @output)
  end

  def test_build_task_content_uses_icon_for_pending_state
    task_class = stub_task_class("MyTask")
    @layout.on_task_updated(task_class, previous_state: nil, current_state: :pending, phase: :run, timestamp: Time.now)

    content = @layout.send(:build_task_content, task_class)
    assert_includes content, "○"
    assert_includes content, "MyTask"
  end

  def test_build_task_content_uses_spinner_for_running_state
    task_class = stub_task_class("MyTask")
    @layout.on_task_updated(task_class, previous_state: nil, current_state: :pending, phase: :run, timestamp: Time.now)
    @layout.on_task_updated(task_class, previous_state: :pending, current_state: :running, phase: :run, timestamp: Time.now)

    content = @layout.send(:build_task_content, task_class)
    assert_includes content, "⠋"
    assert_includes content, "MyTask"
  end

  def test_build_task_content_uses_icon_for_completed_state
    task_class = stub_task_class("MyTask")
    started_at = Time.now
    @layout.on_task_updated(task_class, previous_state: nil, current_state: :pending, phase: :run, timestamp: started_at)
    @layout.on_task_updated(task_class, previous_state: :pending, current_state: :running, phase: :run, timestamp: started_at)
    @layout.on_task_updated(task_class, previous_state: :running, current_state: :completed, phase: :run, timestamp: started_at + 0.1)

    content = @layout.send(:build_task_content, task_class)
    assert_includes content, "✓"
    assert_includes content, "MyTask"
    assert_includes content, "(100"
  end

  def test_build_task_content_uses_icon_for_failed_state
    task_class = stub_task_class("MyTask")
    started_at = Time.now
    @layout.on_task_updated(task_class, previous_state: nil, current_state: :pending, phase: :run, timestamp: started_at)
    @layout.on_task_updated(task_class, previous_state: :pending, current_state: :running, phase: :run, timestamp: started_at)
    @layout.on_task_updated(task_class, previous_state: :running, current_state: :failed, phase: :run, timestamp: started_at + 0.001)

    content = @layout.send(:build_task_content, task_class)
    assert_includes content, "✗"
    assert_includes content, "MyTask"
  end

  private

  def stub_task_class(name)
    klass = Class.new
    klass.define_singleton_method(:name) { name }
    klass.define_singleton_method(:cached_dependencies) { [] }
    klass
  end
end

class TestLayoutTreeEventWithCustomTemplate < Minitest::Test
  include TaskiTestHelper

  def setup
    @output = StringIO.new
  end

  def test_uses_custom_theme_task_start
    custom_theme = Class.new(Taski::Progress::Theme::Base) do
      def task_start
        "[BEGIN] {{ task.name }}"
      end
    end.new

    layout = Taski::Progress::Layout::Tree::Event.new(output: @output, theme: custom_theme)
    task_class = stub_task_class("MyTask")
    layout.on_task_updated(task_class, previous_state: nil, current_state: :pending, phase: :run, timestamp: Time.now)
    layout.on_start
    layout.on_task_updated(task_class, previous_state: :pending, current_state: :running, phase: :run, timestamp: Time.now)
    layout.on_stop

    assert_includes @output.string, "[BEGIN] MyTask"
  end

  def test_tree_prefix_with_custom_theme
    custom_theme = Class.new(Taski::Progress::Theme::Base) do
      def task_start
        "=> {{ task.name }}"
      end
    end.new

    layout = Taski::Progress::Layout::Tree::Event.new(output: @output, theme: custom_theme)

    child = stub_task_class("ChildTask")
    parent = stub_task_class_with_deps("ParentTask", [child])

    ctx = mock_execution_facade(root_task_class: parent)
    layout.context = ctx
    layout.on_ready
    layout.on_start
    layout.on_task_updated(child, previous_state: :pending, current_state: :running, phase: :run, timestamp: Time.now)
    layout.on_stop

    assert_includes @output.string, "└── => ChildTask"
  end

  private

  def stub_task_class(name)
    klass = Class.new
    klass.define_singleton_method(:name) { name }
    klass.define_singleton_method(:cached_dependencies) { [] }
    klass
  end

  def stub_task_class_with_deps(name, deps)
    klass = Class.new
    klass.define_singleton_method(:name) { name }
    klass.define_singleton_method(:cached_dependencies) { deps }
    klass
  end
end

class TestLayoutTreeEventRenderTree < Minitest::Test
  include TaskiTestHelper

  def setup
    @output = StringIO.new
  end

  def test_render_tree_returns_single_task
    theme = Taski::Progress::Theme::Plain.new
    layout = Taski::Progress::Layout::Tree::Event.new(output: @output, theme: theme)
    root = stub_task_class("RootTask")

    ctx = mock_execution_facade(root_task_class: root)
    layout.context = ctx
    layout.on_ready

    result = layout.render_tree
    assert_includes result, "RootTask"
  end

  def test_render_tree_returns_multi_level_tree
    theme = Taski::Progress::Theme::Plain.new
    layout = Taski::Progress::Layout::Tree::Event.new(output: @output, theme: theme)

    leaf = stub_task_class("LeafTask")
    middle = stub_task_class_with_deps("MiddleTask", [leaf])
    root = stub_task_class_with_deps("RootTask", [middle])

    ctx = mock_execution_facade(root_task_class: root)
    layout.context = ctx
    layout.on_ready

    result = layout.render_tree
    assert_includes result, "RootTask"
    assert_includes result, "└── [PENDING] MiddleTask"
    assert_includes result, "    └── [PENDING] LeafTask"
  end

  def test_render_tree_returns_multiple_children
    theme = Taski::Progress::Theme::Plain.new
    layout = Taski::Progress::Layout::Tree::Event.new(output: @output, theme: theme)

    child1 = stub_task_class("Child1")
    child2 = stub_task_class("Child2")
    root = stub_task_class_with_deps("RootTask", [child1, child2])

    ctx = mock_execution_facade(root_task_class: root)
    layout.context = ctx
    layout.on_ready

    result = layout.render_tree
    assert_includes result, "├── [PENDING] Child1"
    assert_includes result, "└── [PENDING] Child2"
  end

  private

  def stub_task_class(name)
    klass = Class.new
    klass.define_singleton_method(:name) { name }
    klass.define_singleton_method(:cached_dependencies) { [] }
    klass
  end

  def stub_task_class_with_deps(name, deps)
    klass = Class.new
    klass.define_singleton_method(:name) { name }
    klass.define_singleton_method(:cached_dependencies) { deps }
    klass
  end
end
