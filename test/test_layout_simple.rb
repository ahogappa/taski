# frozen_string_literal: true

require "test_helper"
require "stringio"
require "taski/execution/layout/simple"

class TestLayoutSimple < Minitest::Test
  def setup
    @output = StringIO.new
    # Stub tty? to return true for testing
    @output.define_singleton_method(:tty?) { true }
    @layout = Taski::Execution::Layout::Simple.new(output: @output)
  end

  # === TTY detection ===

  def test_does_not_activate_for_non_tty
    non_tty_output = StringIO.new
    layout = Taski::Execution::Layout::Simple.new(output: non_tty_output)
    layout.start
    layout.stop

    # Should not output anything (no cursor hide/show)
    refute_includes non_tty_output.string, "\e[?25l"
  end

  def test_activates_for_tty
    @layout.start
    @layout.stop

    # Should have cursor hide/show escape codes
    assert_includes @output.string, "\e[?25l"  # Hide cursor
    assert_includes @output.string, "\e[?25h"  # Show cursor
  end

  # === Task state updates ===

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

  # === Final output ===

  def test_outputs_success_summary_when_all_tasks_complete
    task_class = stub_task_class("MyTask")
    @layout.register_task(task_class)
    @layout.start
    @layout.update_task(task_class, state: :running)
    @layout.update_task(task_class, state: :completed, duration: 100)
    @layout.stop

    # Should include success icon and task count
    assert_includes @output.string, "✓"
    assert_includes @output.string, "[1/1]"
    assert_includes @output.string, "All tasks completed"
  end

  def test_outputs_failure_summary_when_task_fails
    task_class = stub_task_class("FailedTask")
    @layout.register_task(task_class)
    @layout.start
    @layout.update_task(task_class, state: :running)
    @layout.update_task(task_class, state: :failed, error: StandardError.new("oops"))
    @layout.stop

    # Should include failure icon and error info
    assert_includes @output.string, "✗"
    assert_includes @output.string, "FailedTask"
    assert_includes @output.string, "failed"
  end

  # === Spinner animation ===

  def test_spinner_frames_defined
    assert_equal 10, Taski::Execution::Layout::Simple::SPINNER_FRAMES.size
  end

  # === Section impl handling ===

  def test_register_section_impl_registers_impl
    section_class = stub_task_class("MySection")
    impl_class = stub_task_class("MyImpl")
    @layout.register_task(section_class)
    @layout.register_section_impl(section_class, impl_class)

    assert @layout.task_registered?(impl_class)
  end

  def test_register_section_impl_marks_section_completed
    section_class = stub_task_class("MySection")
    impl_class = stub_task_class("MyImpl")
    @layout.register_task(section_class)
    @layout.register_section_impl(section_class, impl_class)

    # Section should be marked as completed (represented by its impl)
    assert_equal :completed, @layout.task_state(section_class)
  end

  # === Root task tree building ===

  def test_builds_tree_structure_on_root_task_set
    # This is a basic test to ensure tree building doesn't crash
    root_task = stub_task_class("RootTask")
    @layout.set_root_task(root_task)

    # Layout should have registered the root task
    assert @layout.task_registered?(root_task)
  end

  # === Icon and color constants ===

  def test_icons_defined
    icons = Taski::Execution::Layout::Simple::ICONS
    assert_equal "✓", icons[:success]
    assert_equal "✗", icons[:failure]
    assert_equal "○", icons[:pending]
  end

  def test_colors_defined
    colors = Taski::Execution::Layout::Simple::COLORS
    assert_equal "\e[32m", colors[:green]
    assert_equal "\e[31m", colors[:red]
    assert_equal "\e[33m", colors[:yellow]
    assert_equal "\e[0m", colors[:reset]
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

class TestLayoutSimpleWithTreeProgressDisplay < Minitest::Test
  # These tests verify the Simple layout works when TreeProgressDisplay's
  # tree building method is available

  def setup
    @output = StringIO.new
    @output.define_singleton_method(:tty?) { true }
    @layout = Taski::Execution::Layout::Simple.new(output: @output)
  end

  def test_tree_building_uses_tree_progress_display_method
    # If TreeProgressDisplay is available, it should use its tree building
    if defined?(Taski::Execution::TreeProgressDisplay)
      root = Taski::Task
      # Just verify it doesn't crash when TreeProgressDisplay is available
      @layout.set_root_task(root)
    end
  end
end
