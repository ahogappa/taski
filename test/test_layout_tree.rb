# frozen_string_literal: true

require "test_helper"
require "stringio"
require "taski/progress/layout/tree"
require "taski/progress/theme/default"

class TestLayoutTree < Minitest::Test
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

  def test_registers_root_task_on_set_root_task
    root_task = stub_task_class("RootTask")
    @layout.set_root_task(root_task)
    assert @layout.task_registered?(root_task)
  end

  def test_tracks_task_state
    task_class = stub_task_class("MyTask")
    @layout.register_task(task_class)
    @layout.update_task(task_class, state: :running)
    assert_equal :running, @layout.task_state(task_class)
  end

  def test_tracks_completed_task
    task_class = stub_task_class("MyTask")
    @layout.register_task(task_class)
    @layout.update_task(task_class, state: :running)
    @layout.update_task(task_class, state: :completed, duration: 100)
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

class TestLayoutTreeRendering < Minitest::Test
  def setup
    @output = StringIO.new
    @layout = Taski::Progress::Layout::Tree.new(output: @output)
  end

  # Test that Layout::Tree uses Theme::Detail by default with icons/spinner

  def test_outputs_task_start_with_spinner
    task_class = stub_task_class("MyTask")
    @layout.register_task(task_class)
    @layout.start
    @layout.update_task(task_class, state: :running)
    @layout.stop

    # Theme::Detail uses spinner for running tasks
    assert_includes @output.string, "⠋ MyTask"
  end

  def test_outputs_task_success_with_icon_and_duration
    task_class = stub_task_class("MyTask")
    @layout.register_task(task_class)
    @layout.start
    @layout.update_task(task_class, state: :running)
    @layout.update_task(task_class, state: :completed, duration: 123)
    @layout.stop

    # Theme::Detail uses ✓ icon for completed tasks
    assert_includes @output.string, "✓"
    assert_includes @output.string, "MyTask"
    assert_includes @output.string, "(123ms)"
  end

  def test_outputs_task_fail_with_icon_and_error
    task_class = stub_task_class("MyTask")
    @layout.register_task(task_class)
    @layout.start
    @layout.update_task(task_class, state: :running)
    @layout.update_task(task_class, state: :failed, error: StandardError.new("Something went wrong"))
    @layout.stop

    # Theme::Detail uses ✗ icon for failed tasks
    assert_includes @output.string, "✗"
    assert_includes @output.string, "MyTask"
    assert_includes @output.string, "Something went wrong"
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
    @layout.update_task(task_class, state: :running)
    @layout.update_task(task_class, state: :completed, duration: 100)
    @layout.stop

    assert_includes @output.string, "[TASKI] Completed: 1/1 tasks"
  end

  def test_outputs_execution_fail
    task_class = stub_task_class("RootTask")
    @layout.set_root_task(task_class)
    @layout.register_task(task_class)
    @layout.start
    @layout.update_task(task_class, state: :running)
    @layout.update_task(task_class, state: :failed, error: StandardError.new("oops"))
    @layout.stop

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

class TestLayoutTreePrefix < Minitest::Test
  def setup
    @output = StringIO.new
    @layout = Taski::Progress::Layout::Tree.new(output: @output)
  end

  def test_tree_prefix_for_single_child
    # Create a parent with one child
    child = stub_task_class("ChildTask")
    parent = stub_task_class_with_deps("ParentTask", [child])

    @layout.set_root_task(parent)
    @layout.start
    @layout.update_task(child, state: :running)
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

    @layout.set_root_task(parent)
    @layout.start
    @layout.update_task(child1, state: :running)
    @layout.update_task(child2, state: :running)
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

    @layout.set_root_task(parent)
    @layout.start
    @layout.update_task(child, state: :running)
    @layout.update_task(grandchild, state: :running)
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

    @layout.set_root_task(parent)
    @layout.start
    @layout.update_task(child1, state: :running)
    @layout.update_task(grandchild, state: :running)
    @layout.update_task(child2, state: :running)
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
    @layout.set_root_task(root)
    @layout.start
    @layout.update_task(root, state: :running)
    @layout.stop

    output = @output.string
    # Root task should NOT have tree prefix, but should have spinner
    assert_includes output, "⠋ RootTask"
    # But should not have the prefix before it
    refute_includes output, "├── ⠋ RootTask"
    refute_includes output, "└── ⠋ RootTask"
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

class TestLayoutTreeTaskContent < Minitest::Test
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
    @layout.update_task(task_class, state: :running)

    content = @layout.send(:build_task_content, task_class)
    # Theme::Detail uses spinner for running
    assert_includes content, "⠋"
    assert_includes content, "MyTask"
  end

  def test_build_task_content_uses_icon_for_completed_state
    task_class = stub_task_class("MyTask")
    @layout.register_task(task_class)
    @layout.update_task(task_class, state: :completed, duration: 100)

    content = @layout.send(:build_task_content, task_class)
    # Theme::Detail uses ✓ icon for completed
    assert_includes content, "✓"
    assert_includes content, "MyTask"
    assert_includes content, "(100ms)"
  end

  def test_build_task_content_uses_icon_for_failed_state
    task_class = stub_task_class("MyTask")
    @layout.register_task(task_class)
    @layout.update_task(task_class, state: :failed, error: StandardError.new("Something went wrong"))

    content = @layout.send(:build_task_content, task_class)
    # Theme::Detail uses ✗ icon for failed
    assert_includes content, "✗"
    assert_includes content, "MyTask"
    assert_includes content, "Something went wrong"
  end

  private

  def stub_task_class(name)
    klass = Class.new
    klass.define_singleton_method(:name) { name }
    klass.define_singleton_method(:cached_dependencies) { [] }
    klass
  end
end

class TestLayoutTreeWithCustomTemplate < Minitest::Test
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
    layout.update_task(task_class, state: :running)
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
    layout.update_task(task_class, state: :completed, duration: 100)
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

    layout.set_root_task(parent)
    layout.start
    layout.update_task(child, state: :running)
    layout.stop

    # Tree prefix should combine with custom template
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
