# frozen_string_literal: true

require "test_helper"
require "stringio"
require "taski/progress/layout/tree/live"
require "taski/progress/theme/default"

class TestLayoutTreeLive < Minitest::Test
  include TaskiTestHelper

  def setup
    @output = StringIO.new
    @output.define_singleton_method(:tty?) { true }
    @layout = Taski::Progress::Layout::Tree::Live.new(output: @output)
  end

  def test_inherits_from_layout_base
    assert_kind_of Taski::Progress::Layout::Base, @layout
  end

  def test_includes_tree_structure
    assert_kind_of Taski::Progress::Layout::Tree::Structure, @layout
  end

  def test_can_initialize_with_default_theme
    layout = Taski::Progress::Layout::Tree::Live.new(output: @output)
    assert_instance_of Taski::Progress::Layout::Tree::Live, layout
  end

  def test_can_initialize_with_custom_theme
    theme = Taski::Progress::Theme::Default.new
    layout = Taski::Progress::Layout::Tree::Live.new(output: @output, theme: theme)
    assert_instance_of Taski::Progress::Layout::Tree::Live, layout
  end

  def test_does_not_activate_for_non_tty
    non_tty_output = StringIO.new
    layout = Taski::Progress::Layout::Tree::Live.new(output: non_tty_output)
    layout.on_start
    layout.on_stop
    # Should not output cursor hide/show
    refute_includes non_tty_output.string, "\e[?25l"
  end

  def test_activates_for_tty
    root_task = stub_task_class("RootTask")
    ctx = mock_execution_facade(root_task_class: root_task)
    @layout.context = ctx
    @layout.on_ready
    @layout.on_start
    @layout.on_stop

    assert_includes @output.string, "\e[?25l"  # Hide cursor
    assert_includes @output.string, "\e[?25h"  # Show cursor
  end

  def test_registers_root_task_on_ready
    root_task = stub_task_class("RootTask")
    ctx = mock_execution_facade(root_task_class: root_task)
    @layout.context = ctx
    @layout.on_ready
    assert @layout.task_registered?(root_task)
  end

  def test_outputs_execution_summary_on_stop
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

  def test_outputs_failure_summary_on_stop
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

  def test_tree_prefix_for_children
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

    assert_includes @output.string, "├──"
    assert_includes @output.string, "└──"
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
