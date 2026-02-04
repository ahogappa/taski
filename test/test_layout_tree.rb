# frozen_string_literal: true

require "test_helper"
require "stringio"
require "taski/progress/layout/tree"
require "taski/progress/template/default"

class TestLayoutTree < Minitest::Test
  def setup
    @output = StringIO.new
    @layout = Taski::Progress::Layout::Tree.new(output: @output)
  end

  def test_can_initialize_with_default_template
    layout = Taski::Progress::Layout::Tree.new(output: @output)
    assert_instance_of Taski::Progress::Layout::Tree, layout
  end

  def test_can_initialize_with_custom_template
    template = Taski::Progress::Template::Default.new
    layout = Taski::Progress::Layout::Tree.new(output: @output, template: template)
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
    klass.define_singleton_method(:section?) { false }
    klass
  end
end

class TestLayoutTreeRendering < Minitest::Test
  def setup
    @output = StringIO.new
    @layout = Taski::Progress::Layout::Tree.new(output: @output)
  end

  # Test that Layout::Tree can use Template::Default (Plain's base template)
  # This proves the goal: "Same Template works with different Layouts"

  def test_outputs_task_start_with_template_default
    task_class = stub_task_class("MyTask")
    @layout.register_task(task_class)
    @layout.start
    @layout.update_task(task_class, state: :running)
    @layout.stop

    assert_includes @output.string, "[START] MyTask"
  end

  def test_outputs_task_success_with_duration
    task_class = stub_task_class("MyTask")
    @layout.register_task(task_class)
    @layout.start
    @layout.update_task(task_class, state: :running)
    @layout.update_task(task_class, state: :completed, duration: 123)
    @layout.stop

    assert_includes @output.string, "[DONE] MyTask (123ms)"
  end

  def test_outputs_task_fail_with_error
    task_class = stub_task_class("MyTask")
    @layout.register_task(task_class)
    @layout.start
    @layout.update_task(task_class, state: :running)
    @layout.update_task(task_class, state: :failed, error: StandardError.new("Something went wrong"))
    @layout.stop

    assert_includes @output.string, "[FAIL] MyTask: Something went wrong"
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
    klass.define_singleton_method(:section?) { false }
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

    # Child should have tree prefix
    output = @output.string
    assert_includes output, "└── [START] ChildTask"
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
    # First child should use branch
    assert_includes output, "├── [START] Child1"
    # Last child should use last_branch
    assert_includes output, "└── [START] Child2"
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
    # Child at depth 1
    assert_includes output, "└── [START] ChildTask"
    # Grandchild at depth 2 with proper indentation
    assert_includes output, "    └── [START] GrandChild"
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
    # Child1 is not last (has sibling child2)
    assert_includes output, "├── [START] Child1"
    # Grandchild should have vertical continuation line because child1 has siblings
    assert_includes output, "│   └── [START] GrandChild"
    # Child2 is last
    assert_includes output, "└── [START] Child2"
  end

  def test_root_task_has_no_prefix
    root = stub_task_class("RootTask")
    @layout.set_root_task(root)
    @layout.start
    @layout.update_task(root, state: :running)
    @layout.stop

    output = @output.string
    # Root task should NOT have tree prefix
    assert_includes output, "[START] RootTask"
    # But should not have the prefix before it
    refute_includes output, "├── [START] RootTask"
    refute_includes output, "└── [START] RootTask"
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

class TestLayoutTreeOutputCapture < Minitest::Test
  def setup
    @output = StringIO.new
    @layout = Taski::Progress::Layout::Tree.new(output: @output)
  end

  # Test build_output_suffix method directly (used in TTY mode live rendering)

  def test_build_output_suffix_returns_last_line
    mock_capture = Object.new
    task_class = stub_task_class("MyTask")

    mock_capture.define_singleton_method(:last_line_for) do |tc|
      (tc == task_class) ? "Processing data..." : nil
    end

    @layout.set_output_capture(mock_capture)

    suffix = @layout.send(:build_output_suffix, task_class)
    assert_equal "Processing data...", suffix
  end

  def test_build_output_suffix_returns_nil_without_capture
    task_class = stub_task_class("MyTask")

    suffix = @layout.send(:build_output_suffix, task_class)
    assert_nil suffix
  end

  def test_build_output_suffix_returns_nil_for_empty_line
    mock_capture = Object.new
    task_class = stub_task_class("MyTask")

    mock_capture.define_singleton_method(:last_line_for) do |tc|
      (tc == task_class) ? "   " : nil
    end

    @layout.set_output_capture(mock_capture)

    suffix = @layout.send(:build_output_suffix, task_class)
    assert_nil suffix
  end

  def test_build_output_suffix_returns_full_output
    mock_capture = Object.new
    task_class = stub_task_class("MyTask")

    long_output = "A" * 100
    mock_capture.define_singleton_method(:last_line_for) do |tc|
      (tc == task_class) ? long_output : nil
    end

    @layout.set_output_capture(mock_capture)

    # build_output_suffix no longer truncates; truncation is done by template's truncate_text filter
    suffix = @layout.send(:build_output_suffix, task_class)
    assert_equal long_output, suffix
  end

  def test_build_output_suffix_strips_whitespace
    mock_capture = Object.new
    task_class = stub_task_class("MyTask")

    mock_capture.define_singleton_method(:last_line_for) do |tc|
      (tc == task_class) ? "  output with spaces  \n" : nil
    end

    @layout.set_output_capture(mock_capture)

    suffix = @layout.send(:build_output_suffix, task_class)
    assert_equal "output with spaces", suffix
  end

  def test_build_task_content_includes_output_suffix_for_running
    mock_capture = Object.new
    task_class = stub_task_class("MyTask")

    mock_capture.define_singleton_method(:last_line_for) do |tc|
      (tc == task_class) ? "Processing..." : nil
    end

    @layout.set_output_capture(mock_capture)
    @layout.register_task(task_class)
    @layout.update_task(task_class, state: :running)

    content = @layout.send(:build_task_content, task_class)
    assert_includes content, "MyTask"
    assert_includes content, "| Processing..."
  end

  def test_build_task_content_excludes_output_suffix_for_completed
    mock_capture = Object.new
    task_class = stub_task_class("MyTask")

    mock_capture.define_singleton_method(:last_line_for) do |tc|
      (tc == task_class) ? "Final output" : nil
    end

    @layout.set_output_capture(mock_capture)
    @layout.register_task(task_class)
    @layout.update_task(task_class, state: :completed, duration: 100)

    content = @layout.send(:build_task_content, task_class)
    assert_includes content, "MyTask"
    refute_includes content, "Final output"
    refute_includes content, "|"
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
  def setup
    @output = StringIO.new
  end

  def test_uses_custom_template_task_start
    custom_template = Class.new(Taski::Progress::Template::Base) do
      def task_start
        "[BEGIN] {{ task_name }}"
      end
    end.new

    layout = Taski::Progress::Layout::Tree.new(output: @output, template: custom_template)
    task_class = stub_task_class("MyTask")
    layout.register_task(task_class)
    layout.start
    layout.update_task(task_class, state: :running)
    layout.stop

    assert_includes @output.string, "[BEGIN] MyTask"
  end

  def test_uses_custom_template_task_success
    custom_template = Class.new(Taski::Progress::Template::Base) do
      def task_success
        "[OK] {{ task_name }}"
      end
    end.new

    layout = Taski::Progress::Layout::Tree.new(output: @output, template: custom_template)
    task_class = stub_task_class("MyTask")
    layout.register_task(task_class)
    layout.start
    layout.update_task(task_class, state: :completed, duration: 100)
    layout.stop

    assert_includes @output.string, "[OK] MyTask"
  end

  def test_tree_prefix_with_custom_template
    custom_template = Class.new(Taski::Progress::Template::Base) do
      def task_start
        "=> {{ task_name }}"
      end
    end.new

    layout = Taski::Progress::Layout::Tree.new(output: @output, template: custom_template)

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
