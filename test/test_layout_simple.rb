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
    @layout = Taski::Progress::Layout::Simple::Display.new(output: @output)
  end

  # === TTY detection ===

  def test_does_not_activate_for_non_tty
    non_tty_output = StringIO.new
    layout = Taski::Progress::Layout::Simple::Display.new(output: non_tty_output)
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

  def test_skipped_count_is_passed_to_completion_template
    custom_theme = Class.new(Taski::Progress::Theme::Base) do
      def icon_success = "✓"

      def execution_complete(execution:, task: nil)
        "#{icon_for(execution.state)} [TASKI] Completed: #{execution.done_count}/#{execution.total_count} tasks (#{execution.skipped_count} skipped)"
      end
    end.new

    layout = Taski::Progress::Layout::Simple::Display.new(output: @output, theme: custom_theme)
    task_a = stub_task_class("TaskA")
    task_b = stub_task_class("TaskB")
    now = Time.now

    # Register both tasks as pending
    layout.on_task_updated(task_a, previous_state: nil, current_state: :pending, phase: :run, timestamp: now)
    layout.on_task_updated(task_b, previous_state: nil, current_state: :pending, phase: :run, timestamp: now)
    layout.on_start

    # TaskA completes, TaskB is skipped
    layout.on_task_updated(task_a, previous_state: :pending, current_state: :running, phase: :run, timestamp: now)
    layout.on_task_updated(task_a, previous_state: :running, current_state: :completed, phase: :run, timestamp: now + 0.1)
    layout.on_task_updated(task_b, previous_state: :pending, current_state: :skipped, phase: :run, timestamp: now + 0.1)
    layout.on_stop

    assert_includes @output.string, "2/2 tasks (1 skipped)"
  end

  # === Task name ordering ===

  def test_displays_most_recently_started_tasks_first
    root_task = stub_task_class("RootTask")
    middle_task = stub_task_class("MiddleTask")
    leaf_task = stub_task_class("LeafTask")
    now = Time.now

    # Start tasks in order: root first, leaf last
    [root_task, middle_task, leaf_task].each do |task|
      @layout.on_task_updated(task, previous_state: nil, current_state: :pending, phase: :run, timestamp: now)
    end
    [root_task, middle_task, leaf_task].each do |task|
      @layout.on_task_updated(task, previous_state: :pending, current_state: :running, phase: :run, timestamp: now)
    end

    task_names = @layout.send(:collect_current_task_names)

    # Most recently started tasks should appear first
    assert_equal %w[LeafTask MiddleTask RootTask], task_names
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

  # === Group name in the status line ===
  # Documented contract (GUIDE "Group Blocks"): while a group is open, the
  # status line shows "| GroupName: output..." for the primary task — but
  # only for output emitted under that group; lines captured BEFORE the
  # group opened must not be captioned with the new group's name.

  def test_status_line_prefixes_output_emitted_under_the_group
    task = stub_task_class("DeployTask")
    lines = {}
    capture = stub_output_capture(lines)
    @layout.context = mock_execution_facade(root_task_class: task, output_capture: capture)
    @layout.on_ready
    now = Time.now
    @layout.on_task_updated(task, previous_state: :pending, current_state: :running, phase: :run, timestamp: now)
    @layout.on_group_started(task, "Deploying", phase: :run, timestamp: now)
    lines[task] = "Uploading files..." # captured AFTER the group opened

    line = @layout.send(:build_status_line)

    assert_includes line, "| Deploying: Uploading files..."
  end

  def test_status_line_shows_group_name_alone_when_no_output_yet
    task = stub_task_class("DeployTask")
    capture = stub_output_capture({})
    @layout.context = mock_execution_facade(root_task_class: task, output_capture: capture)
    @layout.on_ready
    now = Time.now
    @layout.on_task_updated(task, previous_state: :pending, current_state: :running, phase: :run, timestamp: now)
    @layout.on_group_started(task, "Preparing environment", phase: :run, timestamp: now)

    line = @layout.send(:build_status_line)

    assert_includes line, "| Preparing environment"
  end

  def test_status_line_does_not_caption_pre_group_output_with_the_group_name
    task = stub_task_class("DeployTask")
    lines = {task => "line from the previous phase"}
    capture = stub_output_capture(lines)
    @layout.context = mock_execution_facade(root_task_class: task, output_capture: capture)
    @layout.on_ready
    now = Time.now
    @layout.on_task_updated(task, previous_state: :pending, current_state: :running, phase: :run, timestamp: now)
    # The group opens while the pre-group line is still the latest capture —
    # a quiet group must show its name alone, not claim the old output.
    @layout.on_group_started(task, "Deploying", phase: :run, timestamp: now)

    line = @layout.send(:build_status_line)

    assert_includes line, "| Deploying"
    refute_includes line, "previous phase"
  end

  def test_status_line_drops_group_prefix_after_group_completes
    task = stub_task_class("DeployTask")
    capture = stub_output_capture(task => "Uploading files...")
    @layout.context = mock_execution_facade(root_task_class: task, output_capture: capture)
    @layout.on_ready
    now = Time.now
    @layout.on_task_updated(task, previous_state: :pending, current_state: :running, phase: :run, timestamp: now)
    @layout.on_group_started(task, "Deploying", phase: :run, timestamp: now)
    @layout.on_group_completed(task, "Deploying", phase: :run, timestamp: now + 1)

    line = @layout.send(:build_status_line)

    assert_includes line, "| Uploading files..."
    refute_includes line, "Deploying"
  end

  # Layout-level robustness: if overlapping group events arrive (Task#group
  # forbids nesting, but the layout must tolerate whatever events come), the
  # most recently started open group wins, and each group only captions
  # output emitted while it was the active one.
  def test_status_line_uses_most_recently_started_open_group
    task = stub_task_class("DeployTask")
    lines = {}
    capture = stub_output_capture(lines)
    @layout.context = mock_execution_facade(root_task_class: task, output_capture: capture)
    @layout.on_ready
    now = Time.now
    @layout.on_task_updated(task, previous_state: :pending, current_state: :running, phase: :run, timestamp: now)
    @layout.on_group_started(task, "Outer", phase: :run, timestamp: now)
    @layout.on_group_started(task, "Inner", phase: :run, timestamp: now + 0.1)
    lines[task] = "inner step"

    assert_includes @layout.send(:build_status_line), "| Inner: inner step"

    @layout.on_group_completed(task, "Inner", phase: :run, timestamp: now + 0.2)
    # back under Outer: the inner line is not Outer's — name alone until
    # Outer emits something new
    assert_includes @layout.send(:build_status_line), "| Outer"
    refute_includes @layout.send(:build_status_line), "inner step"

    lines[task] = "outer step"
    assert_includes @layout.send(:build_status_line), "| Outer: outer step"
  end

  def test_status_line_group_prefix_is_per_task
    grouped = stub_task_class("GroupedTask")
    other = stub_task_class("OtherTask")
    capture = stub_output_capture(other => "other output")
    @layout.context = mock_execution_facade(root_task_class: grouped, output_capture: capture)
    @layout.on_ready
    now = Time.now
    @layout.on_task_updated(grouped, previous_state: :pending, current_state: :running, phase: :run, timestamp: now)
    @layout.on_group_started(grouped, "Bundling", phase: :run, timestamp: now)
    # `other` starts later, becoming the primary task — its line must NOT get
    # the group prefix of a different task
    @layout.on_task_updated(other, previous_state: :pending, current_state: :running, phase: :run, timestamp: now + 0.1)

    line = @layout.send(:build_status_line)

    assert_includes line, "| other output"
    refute_includes line, "Bundling"
  end

  def test_status_line_truncates_long_group_names_when_output_present
    task = stub_task_class("DeployTask")
    lines = {}
    capture = stub_output_capture(lines)
    @layout.context = mock_execution_facade(root_task_class: task, output_capture: capture)
    @layout.on_ready
    now = Time.now
    @layout.on_task_updated(task, previous_state: :pending, current_state: :running, phase: :run, timestamp: now)
    @layout.on_group_started(task, "Synchronizing all the deployment artifacts", phase: :run, timestamp: now)
    lines[task] = "uploading"

    line = @layout.send(:build_status_line)

    # The label is capped (15 chars incl. suffix) so the output keeps budget
    # within the 40-char stdout window; the full name still shows when there
    # is no output.
    assert_includes line, "| Synchronizin...: uploading"
  end

  private

  def stub_task_class(name)
    klass = Class.new
    klass.define_singleton_method(:name) { name }
    klass.define_singleton_method(:cached_dependencies) { [] }
    klass
  end

  def stub_output_capture(lines_by_task)
    capture = Object.new
    capture.define_singleton_method(:last_line_for) { |tc| lines_by_task[tc] }
    capture
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

    layout = Taski::Progress::Layout::Simple::Display.new(output: @output, theme: custom_theme)

    # Verify custom theme is accepted by layout (no error on construction)
    assert_instance_of Taski::Progress::Layout::Simple::Display, layout
    assert_equal %w[🌑 🌒 🌓 🌔 🌕 🌖 🌗 🌘], custom_theme.spinner_frames
  end

  # === Custom render interval ===

  def test_uses_custom_render_interval_from_template
    custom_theme = Class.new(Taski::Progress::Theme::Base) do
      def render_interval
        0.2
      end
    end.new

    layout = Taski::Progress::Layout::Simple::Display.new(output: @output, theme: custom_theme)

    # Verify custom theme is accepted by layout (no error on construction)
    assert_instance_of Taski::Progress::Layout::Simple::Display, layout
    assert_in_delta 0.2, custom_theme.render_interval, 0.001
  end

  # === Custom icons ===

  def test_uses_custom_icons_in_final_output
    custom_theme = Class.new(Taski::Progress::Theme::Base) do
      def icon_success
        "🎉"
      end

      def execution_complete(execution:, task: nil)
        "#{icon_for(execution.state)} Done!"
      end
    end.new

    layout = Taski::Progress::Layout::Simple::Display.new(output: @output, theme: custom_theme)
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

      def execution_fail(execution:, task: nil)
        "#{icon_for(execution.state)} Boom! #{execution.failed_count}/#{execution.total_count}"
      end
    end.new

    layout = Taski::Progress::Layout::Simple::Display.new(output: @output, theme: custom_theme)
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
      def execution_complete(execution:, task: nil)
        "#{icon_for(execution.state)} Finished #{execution.done_count} tasks in #{format_duration(execution.total_duration)}"
      end
    end.new

    layout = Taski::Progress::Layout::Simple::Display.new(output: @output, theme: custom_theme)
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

      # Override to use the state icon helper
      def execution_complete(execution:, task: nil)
        "#{icon_for(execution.state)} Done!"
      end
    end.new

    layout = Taski::Progress::Layout::Simple::Display.new(output: @output, theme: custom_theme)
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
