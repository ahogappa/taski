# frozen_string_literal: true

require "test_helper"
require_relative "fixtures/parallel_tasks"

class TestSimpleProgressDisplay < Minitest::Test
  def setup
    Taski.reset_progress_display!
    @output = StringIO.new
    @display = Taski::Progress::Layout::Simple.new(output: @output)
  end

  def teardown
    Taski.reset_progress_display!
  end

  def test_register_task
    @display.register_task(FixtureTaskA)
    assert @display.task_registered?(FixtureTaskA)
  end

  def test_task_registered_returns_false_for_unregistered_task
    refute @display.task_registered?(FixtureTaskA)
  end

  def test_register_task_is_idempotent
    @display.register_task(FixtureTaskA)
    @display.register_task(FixtureTaskA)
    assert @display.task_registered?(FixtureTaskA)
  end

  def test_update_task_state
    @display.register_task(FixtureTaskA)
    @display.update_task(FixtureTaskA, state: :running)
    assert_equal :running, @display.task_state(FixtureTaskA)
  end

  def test_update_task_state_to_completed
    @display.register_task(FixtureTaskA)
    @display.update_task(FixtureTaskA, state: :running)
    @display.update_task(FixtureTaskA, state: :completed, duration: 100)
    assert_equal :completed, @display.task_state(FixtureTaskA)
  end

  def test_update_task_state_to_failed
    @display.register_task(FixtureTaskA)
    @display.update_task(FixtureTaskA, state: :running)
    @display.update_task(FixtureTaskA, state: :failed, error: StandardError.new("test error"))
    assert_equal :failed, @display.task_state(FixtureTaskA)
  end

  def test_task_state_returns_nil_for_unregistered_task
    assert_nil @display.task_state(FixtureTaskA)
  end

  def test_set_root_task
    @display.set_root_task(FixtureTaskB)
    # After setting root task, the root and its dependencies should be registered
    assert @display.task_registered?(FixtureTaskB)
    assert @display.task_registered?(FixtureTaskA)
  end

  def test_set_root_task_is_idempotent
    @display.set_root_task(FixtureTaskB)
    @display.set_root_task(FixtureTaskA) # Should be ignored
    # Only the first root task's dependencies should be registered
    assert @display.task_registered?(FixtureTaskB)
    assert @display.task_registered?(FixtureTaskA)
  end

  def test_start_and_stop_without_tty
    # When output is not a TTY, start should do nothing
    @display.start
    @display.stop
    # No error should be raised
    assert true
  end

  def test_nested_start_stop_calls
    @display.start
    @display.start
    @display.stop
    # Should still be in started state (nest_level > 0)
    @display.stop
    # Now fully stopped
    assert true
  end

  def test_set_output_capture
    mock_capture = Object.new
    @display.set_output_capture(mock_capture)
    # Verify no error raised
    assert true
  end

  def test_set_output_capture_with_nil
    @display.set_output_capture(nil)
    # Verify no error raised
    assert true
  end

  def test_update_group
    @display.register_task(FixtureTaskA)
    @display.update_group(FixtureTaskA, "test_group", state: :running)
    # Should not raise error
    assert true
  end
end

class TestSimpleProgressDisplayWithTTY < Minitest::Test
  # Create a StringIO that reports itself as a TTY
  class TTYStringIO < StringIO
    def tty?
      true
    end

    def isatty
      true
    end

    def winsize
      [24, 80]
    end
  end

  def setup
    Taski.reset_progress_display!
    @output = TTYStringIO.new
    @display = Taski::Progress::Layout::Simple.new(output: @output)
  end

  def teardown
    @display&.stop
    Taski.reset_progress_display!
  end

  def test_start_with_tty_starts_renderer_thread
    @display.set_root_task(FixtureTaskB)
    @display.start
    sleep 0.05
    @display.stop

    output = @output.string
    # Should include cursor hide/show sequences
    assert_includes output, "\e[?25l"
    assert_includes output, "\e[?25h"
  end

  def test_render_shows_task_count
    @display.set_root_task(FixtureTaskB)
    @display.start
    @display.update_task(FixtureTaskA, state: :running)
    sleep 0.05

    output = @output.string
    # Should include task count format like [0/2] or [1/2]
    assert_match(/\[\d+\/\d+\]/, output)
  end

  def test_render_shows_running_task_name
    @display.set_root_task(FixtureTaskB)
    @display.start
    @display.update_task(FixtureTaskA, state: :running)
    sleep 0.05

    output = @output.string
    assert_includes output, "FixtureTaskA"
  end

  def test_render_shows_checkmark_for_completed_task
    @display.set_root_task(FixtureTaskB)
    @display.start
    @display.update_task(FixtureTaskA, state: :completed, duration: 100)
    sleep 0.05

    output = @output.string
    # Spinner or checkmark should appear
    assert_match(/[✓⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏]/, output)
  end

  def test_render_shows_x_for_failed_task
    @display.set_root_task(FixtureTaskB)
    @display.start
    @display.update_task(FixtureTaskA, state: :failed, error: StandardError.new("test error"))
    @display.stop

    output = @output.string
    # X mark should appear in final render after stop
    assert_match(/[✗✕×]/, output)
  end

  def test_render_shows_multiple_running_tasks
    @display.set_root_task(FixtureNamespace::TaskD)
    @display.start
    @display.update_task(FixtureTaskA, state: :running)
    @display.update_task(FixtureNamespace::TaskC, state: :running)
    sleep 0.05

    output = @output.string
    # Both task names should appear
    assert_includes output, "FixtureTaskA"
    assert_includes output, "TaskC"
  end

  def test_final_render_shows_completion
    @display.set_root_task(FixtureTaskB)
    @display.start
    @display.update_task(FixtureTaskA, state: :completed, duration: 50)
    @display.update_task(FixtureTaskB, state: :completed, duration: 100)
    @display.stop

    output = @output.string
    # Should show checkmark and completion message
    assert_match(/✓/, output)
  end

  def test_simple_mode_uses_single_line
    @display.set_root_task(FixtureTaskB)
    @display.start
    @display.update_task(FixtureTaskA, state: :running)
    sleep 0.05

    output = @output.string
    # Single-line mode should use carriage return for updates
    assert_includes output, "\r"
    # Should NOT use alternate screen buffer
    refute_includes output, "\e[?1049h"
  end

  def test_render_live_overwrites_same_line
    @display.set_root_task(FixtureTaskB)
    @display.start
    @display.update_task(FixtureTaskA, state: :running)
    sleep 0.15  # Wait for at least one render cycle

    output = @output.string
    # Count occurrences of \r\e[K - should have multiple (from render cycles)
    carriage_returns = output.scan("\r\e[K").count

    @display.stop

    final_output = @output.string
    # Live rendering should not add newlines
    # Only the final render should have a newline
    assert carriage_returns > 0, "Should have carriage return sequences during live rendering"
    assert_equal 1, final_output.count("\n"), "Should only have one newline (from final render)"
  end

  def test_render_live_respects_terminal_width
    @display.set_root_task(FixtureTaskB)
    @display.start
    @display.update_task(FixtureTaskA, state: :running)
    sleep 0.15 # Wait for at least one render cycle
    @display.stop

    # Extract live render lines and verify none exceed terminal width (80)
    live_lines = @output.string.scan(/\r\e\[K([^\r\n]*)/).flatten
    assert(live_lines.all? { |line| line.length < 80 }, "Lines should not exceed terminal width")
  end
end

class TestProgressDisplayConfiguration < Minitest::Test
  def setup
    Taski.reset_progress_display!
  end

  def teardown
    Taski.reset_progress_display!
  end

  def test_default_progress_display_is_simple
    display = Taski.progress_display
    assert_instance_of Taski::Progress::Layout::Simple, display
  end

  def test_progress_display_can_be_set_to_nil
    Taski.progress_display = nil
    assert_nil Taski.progress_display
  end

  def test_progress_display_can_be_set_to_tree
    tree = Taski::Progress::Layout::Tree.new
    Taski.progress_display = tree
    assert_same tree, Taski.progress_display
  end

  def test_progress_display_can_be_set_to_log
    log = Taski::Progress::Layout::Log.new
    Taski.progress_display = log
    assert_same log, Taski.progress_display
  end

  def test_progress_display_can_be_set_to_custom_object
    custom = Object.new
    Taski.progress_display = custom
    assert_same custom, Taski.progress_display
  end

  def test_reset_progress_display_restores_default
    Taski.progress_display = nil
    Taski.reset_progress_display!
    display = Taski.progress_display
    assert_instance_of Taski::Progress::Layout::Simple, display
  end

  def test_setting_progress_display_stops_previous
    stop_called = false
    old_display = Object.new
    old_display.define_singleton_method(:stop) { stop_called = true }
    Taski.progress_display = old_display

    Taski.progress_display = Taski::Progress::Layout::Simple.new
    assert stop_called, "Previous display should be stopped when setting a new one"
  end

  def test_progress_mode_is_removed
    refute_respond_to Taski, :progress_mode
    refute_respond_to Taski, :progress_mode=
  end

  def test_progress_disabled_is_removed
    refute_respond_to Taski, :progress_disabled?
  end
end
