# frozen_string_literal: true

require "test_helper"
require "stringio"
require "taski/progress/layout/simple"
require "taski/progress/template/simple"

class TestLayoutSimple < Minitest::Test
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

  def test_spinner_frames_loaded_from_template
    # Spinner frames are accessed via template
    template = @layout.instance_variable_get(:@template)
    assert_equal 10, template.spinner_frames.size
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

  # === Icon and color configuration from Template ===

  def test_icons_available_via_template
    template = @layout.instance_variable_get(:@template)
    assert_equal "✓", template.icon_success
    assert_equal "✗", template.icon_failure
    assert_equal "○", template.icon_pending
  end

  def test_colors_available_via_template
    template = @layout.instance_variable_get(:@template)
    assert_equal "\e[32m", template.color_green
    assert_equal "\e[31m", template.color_red
    assert_equal "\e[33m", template.color_yellow
    assert_equal "\e[0m", template.color_reset
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

class TestLayoutSimpleWithCustomTemplate < Minitest::Test
  def setup
    @output = StringIO.new
    @output.define_singleton_method(:tty?) { true }
  end

  # === Custom spinner frames ===

  def test_uses_custom_spinner_frames_from_template
    custom_template = Class.new(Taski::Progress::Template::Base) do
      def spinner_frames
        %w[🌑 🌒 🌓 🌔 🌕 🌖 🌗 🌘]
      end
    end.new

    layout = Taski::Progress::Layout::Simple.new(output: @output, template: custom_template)

    # Verify the layout accesses the custom spinner frames via template
    template = layout.instance_variable_get(:@template)
    assert_equal %w[🌑 🌒 🌓 🌔 🌕 🌖 🌗 🌘], template.spinner_frames
  end

  # === Custom render interval ===

  def test_uses_custom_render_interval_from_template
    custom_template = Class.new(Taski::Progress::Template::Base) do
      def render_interval
        0.2
      end
    end.new

    layout = Taski::Progress::Layout::Simple.new(output: @output, template: custom_template)

    # Verify the layout accesses render interval via template
    template = layout.instance_variable_get(:@template)
    assert_in_delta 0.2, template.render_interval, 0.001
  end

  # === Custom icons ===

  def test_uses_custom_icons_in_final_output
    custom_template = Class.new(Taski::Progress::Template::Base) do
      def icon_success
        "🎉"
      end

      def status_complete
        "{% icon %} Done!"
      end
    end.new

    layout = Taski::Progress::Layout::Simple.new(output: @output, template: custom_template)
    task_class = stub_task_class("MyTask")
    layout.register_task(task_class)
    layout.start
    layout.update_task(task_class, state: :running)
    layout.update_task(task_class, state: :completed, duration: 100)
    layout.stop

    assert_includes @output.string, "🎉"
    assert_includes @output.string, "Done!"
  end

  def test_uses_custom_failure_icon_in_final_output
    custom_template = Class.new(Taski::Progress::Template::Base) do
      def icon_failure
        "💥"
      end

      def status_failed
        "{% icon %} Boom! {{ failed_task_name }}"
      end
    end.new

    layout = Taski::Progress::Layout::Simple.new(output: @output, template: custom_template)
    task_class = stub_task_class("FailedTask")
    layout.register_task(task_class)
    layout.start
    layout.update_task(task_class, state: :running)
    layout.update_task(task_class, state: :failed, error: StandardError.new("oops"))
    layout.stop

    assert_includes @output.string, "💥"
    assert_includes @output.string, "Boom!"
    assert_includes @output.string, "FailedTask"
  end

  # === Custom status templates ===

  def test_uses_custom_status_complete_template
    custom_template = Class.new(Taski::Progress::Template::Base) do
      def status_complete
        "{% icon %} Finished {{ done_count }} tasks in {{ duration | format_duration }}"
      end
    end.new

    layout = Taski::Progress::Layout::Simple.new(output: @output, template: custom_template)
    task_class = stub_task_class("MyTask")
    layout.register_task(task_class)
    layout.start
    layout.update_task(task_class, state: :completed, duration: 100)
    layout.stop

    assert_includes @output.string, "Finished 1 tasks"
  end

  # === No constants needed with template ===

  def test_layout_does_not_require_constants_when_using_template
    custom_template = Class.new(Taski::Progress::Template::Base) do
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
      def status_complete
        "{% icon %} Done!"
      end
    end.new

    layout = Taski::Progress::Layout::Simple.new(output: @output, template: custom_template)
    task_class = stub_task_class("TestTask")
    layout.register_task(task_class)
    layout.start
    layout.update_task(task_class, state: :completed, duration: 50)
    layout.stop

    # Should complete without errors and use custom values
    assert_includes @output.string, "OK"
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
    @layout = Taski::Progress::Layout::Simple.new(output: @output)
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
