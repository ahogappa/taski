# frozen_string_literal: true

require "test_helper"
require "stringio"
require "taski/progress/layout/simple"
require "taski/progress/theme/compact"

class TestLayoutSimple < Minitest::Test
  include TaskiTestHelper

  def setup
    @output = StringIO.new
    # Stub tty? to return true for testing
    @output.define_singleton_method(:tty?) { true }
    @layout = Taski::Progress::Layout::Simple.new(output: @output)
  end

  # === TTY detection ===

  def test_does_not_activate_for_non_tty
    non_tty_output = StringIO.new
    layout = Taski::Progress::Layout::Simple.new(output: non_tty_output)
    layout.on_start
    layout.on_stop

    # Should not output anything (no cursor hide/show)
    refute_includes non_tty_output.string, "\e[?25l"
  end

  def test_activates_for_tty
    @layout.on_start
    @layout.on_stop

    # Should have cursor hide/show escape codes
    assert_includes @output.string, "\e[?25l"  # Hide cursor
    assert_includes @output.string, "\e[?25h"  # Show cursor
  end

  # === Task state updates ===

  def test_tracks_task_state
    task_class = stub_task_class("MyTask")
    now = Time.now
    @layout.on_task_updated(task_class, previous_state: nil, current_state: :pending, phase: :run, timestamp: now)
    @layout.on_task_updated(task_class, previous_state: :pending, current_state: :running, phase: :run, timestamp: now)

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

  # === Final output ===

  def test_outputs_success_summary_when_all_tasks_complete
    task_class = stub_task_class("MyTask")
    started_at = Time.now
    @layout.on_task_updated(task_class, previous_state: nil, current_state: :pending, phase: :run, timestamp: started_at)
    @layout.on_start
    @layout.on_task_updated(task_class, previous_state: :pending, current_state: :running, phase: :run, timestamp: started_at)
    @layout.on_task_updated(task_class, previous_state: :running, current_state: :completed, phase: :run, timestamp: started_at + 0.1)
    @layout.on_stop

    # Should include success icon and task count
    assert_includes @output.string, "✓"
    assert_includes @output.string, "1/1"
    assert_includes @output.string, "Completed"
  end

  def test_outputs_failure_summary_when_task_fails
    task_class = stub_task_class("FailedTask")
    now = Time.now
    @layout.on_task_updated(task_class, previous_state: nil, current_state: :pending, phase: :run, timestamp: now)
    @layout.on_start
    @layout.on_task_updated(task_class, previous_state: :pending, current_state: :running, phase: :run, timestamp: now)
    @layout.on_task_updated(task_class, previous_state: :running, current_state: :failed, phase: :run, timestamp: now)
    @layout.on_stop

    # Should include failure icon and task count
    assert_includes @output.string, "✗"
    assert_includes @output.string, "1/1"
    assert_includes @output.string, "Failed"
  end

  # === Root task tree building ===

  def test_builds_tree_structure_on_root_task_set
    # This is a basic test to ensure tree building doesn't crash
    root_task = stub_task_class("RootTask")
    ctx = mock_execution_facade(root_task_class: root_task)
    @layout.context = ctx
    @layout.on_ready

    # Layout should have registered the root task
    assert @layout.task_registered?(root_task)
  end

  private

  def stub_task_class(name)
    klass = Class.new
    klass.define_singleton_method(:name) { name }
    klass.define_singleton_method(:cached_dependencies) { [] }
    klass
  end
end

class TestLayoutSimpleWithCustomTemplate < Minitest::Test
  def setup
    @output = StringIO.new
    @output.define_singleton_method(:tty?) { true }
  end

  # === Custom spinner frames ===

  def test_uses_custom_spinner_frames_from_template
    custom_theme = Class.new(Taski::Progress::Theme::Base) do
      def spinner_frames
        %w[🌑 🌒 🌓 🌔 🌕 🌖 🌗 🌘]
      end
    end.new

    layout = Taski::Progress::Layout::Simple.new(output: @output, theme: custom_theme)

    # Verify custom theme is accepted by layout (no error on construction)
    assert_instance_of Taski::Progress::Layout::Simple, layout
    assert_equal %w[🌑 🌒 🌓 🌔 🌕 🌖 🌗 🌘], custom_theme.spinner_frames
  end

  # === Custom render interval ===

  def test_uses_custom_render_interval_from_template
    custom_theme = Class.new(Taski::Progress::Theme::Base) do
      def render_interval
        0.2
      end
    end.new

    layout = Taski::Progress::Layout::Simple.new(output: @output, theme: custom_theme)

    # Verify custom theme is accepted by layout (no error on construction)
    assert_instance_of Taski::Progress::Layout::Simple, layout
    assert_in_delta 0.2, custom_theme.render_interval, 0.001
  end

  # === Custom icons ===

  def test_uses_custom_icons_in_final_output
    custom_theme = Class.new(Taski::Progress::Theme::Base) do
      def icon_success
        "🎉"
      end

      def execution_complete
        "{% icon %} Done!"
      end
    end.new

    layout = Taski::Progress::Layout::Simple.new(output: @output, theme: custom_theme)
    task_class = stub_task_class("MyTask")
    started_at = Time.now
    layout.on_task_updated(task_class, previous_state: nil, current_state: :pending, phase: :run, timestamp: started_at)
    layout.on_start
    layout.on_task_updated(task_class, previous_state: :pending, current_state: :running, phase: :run, timestamp: started_at)
    layout.on_task_updated(task_class, previous_state: :running, current_state: :completed, phase: :run, timestamp: started_at + 0.1)
    layout.on_stop

    assert_includes @output.string, "🎉"
    assert_includes @output.string, "Done!"
  end

  def test_uses_custom_failure_icon_in_final_output
    custom_theme = Class.new(Taski::Progress::Theme::Base) do
      def icon_failure
        "💥"
      end

      def execution_fail
        "{% icon %} Boom! {{ execution.failed_count }}/{{ execution.total_count }}"
      end
    end.new

    layout = Taski::Progress::Layout::Simple.new(output: @output, theme: custom_theme)
    task_class = stub_task_class("FailedTask")
    now = Time.now
    layout.on_task_updated(task_class, previous_state: nil, current_state: :pending, phase: :run, timestamp: now)
    layout.on_start
    layout.on_task_updated(task_class, previous_state: :pending, current_state: :running, phase: :run, timestamp: now)
    layout.on_task_updated(task_class, previous_state: :running, current_state: :failed, phase: :run, timestamp: now)
    layout.on_stop

    assert_includes @output.string, "💥"
    assert_includes @output.string, "Boom!"
    assert_includes @output.string, "1/1"
  end

  # === Custom execution templates ===

  def test_uses_custom_execution_complete_template
    custom_theme = Class.new(Taski::Progress::Theme::Base) do
      def execution_complete
        "{% icon %} Finished {{ execution.completed_count }} tasks in {{ execution.total_duration | format_duration }}"
      end
    end.new

    layout = Taski::Progress::Layout::Simple.new(output: @output, theme: custom_theme)
    task_class = stub_task_class("MyTask")
    started_at = Time.now
    layout.on_task_updated(task_class, previous_state: nil, current_state: :pending, phase: :run, timestamp: started_at)
    layout.on_start
    layout.on_task_updated(task_class, previous_state: :pending, current_state: :completed, phase: :run, timestamp: started_at + 0.1)
    layout.on_stop

    assert_includes @output.string, "Finished 1 tasks"
  end

  # === No constants needed with template ===

  def test_layout_does_not_require_constants_when_using_template
    custom_theme = Class.new(Taski::Progress::Theme::Base) do
      def spinner_frames
        %w[A B C]
      end

      def render_interval
        0.5
      end

      def icon_success
        "OK"
      end

      def icon_failure
        "NG"
      end

      def color_green
        ""
      end

      def color_red
        ""
      end

      def color_yellow
        ""
      end

      def color_reset
        ""
      end

      # Override to use icon tag
      def execution_complete
        "{% icon %} Done!"
      end
    end.new

    layout = Taski::Progress::Layout::Simple.new(output: @output, theme: custom_theme)
    task_class = stub_task_class("TestTask")
    started_at = Time.now
    layout.on_task_updated(task_class, previous_state: nil, current_state: :pending, phase: :run, timestamp: started_at)
    layout.on_start
    layout.on_task_updated(task_class, previous_state: :pending, current_state: :completed, phase: :run, timestamp: started_at + 0.05)
    layout.on_stop

    # Should complete without errors and use custom values
    assert_includes @output.string, "OK"
  end

  private

  def stub_task_class(name)
    klass = Class.new
    klass.define_singleton_method(:name) { name }
    klass.define_singleton_method(:cached_dependencies) { [] }
    klass
  end
end
