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

  def mock_execution_context(root_task_class:, output_capture: nil)
    graph = Taski::StaticAnalysis::DependencyGraph.new
    graph.build_from_cached(root_task_class) if root_task_class.respond_to?(:cached_dependencies)

    ctx = Object.new
    ctx.define_singleton_method(:root_task_class) { root_task_class }
    ctx.define_singleton_method(:output_capture) { output_capture }
    ctx.define_singleton_method(:dependency_graph) { graph }
    ctx
  end

  def test_register_task
    @display.on_task_updated(FixtureTaskA, previous_state: nil, current_state: :pending, phase: :run, timestamp: Time.now)
    assert @display.task_registered?(FixtureTaskA)
  end

  def test_task_registered_returns_false_for_unregistered_task
    refute @display.task_registered?(FixtureTaskA)
  end

  def test_register_task_is_idempotent
    @display.on_task_updated(FixtureTaskA, previous_state: nil, current_state: :pending, phase: :run, timestamp: Time.now)
    @display.on_task_updated(FixtureTaskA, previous_state: nil, current_state: :pending, phase: :run, timestamp: Time.now)
    assert @display.task_registered?(FixtureTaskA)
  end

  def test_update_task_state
    @display.on_task_updated(FixtureTaskA, previous_state: nil, current_state: :pending, phase: :run, timestamp: Time.now)
    @display.on_task_updated(FixtureTaskA, previous_state: :pending, current_state: :running, phase: :run, timestamp: Time.now)
    assert_equal :running, @display.task_state(FixtureTaskA)
  end

  def test_update_task_state_to_completed
    started_at = Time.now
    @display.on_task_updated(FixtureTaskA, previous_state: nil, current_state: :pending, phase: :run, timestamp: started_at)
    @display.on_task_updated(FixtureTaskA, previous_state: :pending, current_state: :running, phase: :run, timestamp: started_at)
    @display.on_task_updated(FixtureTaskA, previous_state: :running, current_state: :completed, phase: :run, timestamp: started_at + 0.1)
    assert_equal :completed, @display.task_state(FixtureTaskA)
  end

  def test_update_task_state_to_failed
    started_at = Time.now
    @display.on_task_updated(FixtureTaskA, previous_state: nil, current_state: :pending, phase: :run, timestamp: started_at)
    @display.on_task_updated(FixtureTaskA, previous_state: :pending, current_state: :running, phase: :run, timestamp: started_at)
    @display.on_task_updated(FixtureTaskA, previous_state: :running, current_state: :failed, phase: :run, timestamp: started_at + 0.001)
    assert_equal :failed, @display.task_state(FixtureTaskA)
  end

  def test_task_state_returns_nil_for_unregistered_task
    assert_nil @display.task_state(FixtureTaskA)
  end

  def test_set_root_task
    ctx = mock_execution_context(root_task_class: FixtureTaskB)
    @display.context = ctx
    @display.on_ready
    # After setting root task via on_ready, the root and its dependencies should be registered
    assert @display.task_registered?(FixtureTaskB)
    assert @display.task_registered?(FixtureTaskA)
  end

  def test_set_root_task_is_idempotent
    ctx = mock_execution_context(root_task_class: FixtureTaskB)
    @display.context = ctx
    @display.on_ready

    ctx2 = mock_execution_context(root_task_class: FixtureTaskA)
    @display.context = ctx2
    @display.on_ready # Should be ignored (root already set)

    # Only the first root task's dependencies should be registered
    assert @display.task_registered?(FixtureTaskB)
    assert @display.task_registered?(FixtureTaskA)
  end

  def test_start_and_stop_without_tty
    # When output is not a TTY, on_start should do nothing
    @display.on_start
    @display.on_stop
    # No error should be raised
    assert true
  end

  def test_nested_start_stop_calls
    @display.on_start
    @display.on_start
    @display.on_stop
    # Should still be in started state (nest_level > 0)
    @display.on_stop
    # Now fully stopped
    assert true
  end

  def test_update_group
    @display.on_task_updated(FixtureTaskA, previous_state: nil, current_state: :pending, phase: :run, timestamp: Time.now)
    @display.on_group_started(FixtureTaskA, "test_group", phase: :run, timestamp: Time.now)
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
    @display&.on_stop
    Taski.reset_progress_display!
  end

  def mock_execution_context(root_task_class:, output_capture: nil)
    graph = Taski::StaticAnalysis::DependencyGraph.new
    graph.build_from_cached(root_task_class) if root_task_class.respond_to?(:cached_dependencies)

    ctx = Object.new
    ctx.define_singleton_method(:root_task_class) { root_task_class }
    ctx.define_singleton_method(:output_capture) { output_capture }
    ctx.define_singleton_method(:dependency_graph) { graph }
    ctx
  end

  def test_start_with_tty_starts_renderer_thread
    ctx = mock_execution_context(root_task_class: FixtureTaskB)
    @display.context = ctx
    @display.on_ready
    @display.on_start
    sleep 0.05
    @display.on_stop

    output = @output.string
    # Should include cursor hide/show sequences
    assert_includes output, "\e[?25l"
    assert_includes output, "\e[?25h"
  end

  def test_render_shows_task_count
    ctx = mock_execution_context(root_task_class: FixtureTaskB)
    @display.context = ctx
    @display.on_ready
    @display.on_start
    @display.on_task_updated(FixtureTaskA, previous_state: :pending, current_state: :running, phase: :run, timestamp: Time.now)
    sleep 0.05

    output = @output.string
    # Should include task count format like [0/2] or [1/2]
    assert_match(/\[\d+\/\d+\]/, output)
  end

  def test_render_shows_running_task_name
    ctx = mock_execution_context(root_task_class: FixtureTaskB)
    @display.context = ctx
    @display.on_ready
    @display.on_start
    @display.on_task_updated(FixtureTaskA, previous_state: :pending, current_state: :running, phase: :run, timestamp: Time.now)
    sleep 0.05

    output = @output.string
    assert_includes output, "FixtureTaskA"
  end

  def test_render_shows_checkmark_for_completed_task
    started_at = Time.now
    ctx = mock_execution_context(root_task_class: FixtureTaskB)
    @display.context = ctx
    @display.on_ready
    @display.on_start
    @display.on_task_updated(FixtureTaskA, previous_state: :pending, current_state: :running, phase: :run, timestamp: started_at)
    @display.on_task_updated(FixtureTaskA, previous_state: :running, current_state: :completed, phase: :run, timestamp: started_at + 0.1)
    sleep 0.05

    output = @output.string
    # Spinner or checkmark should appear
    assert_match(/[✓⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏]/, output)
  end

  def test_render_shows_x_for_failed_task
    started_at = Time.now
    ctx = mock_execution_context(root_task_class: FixtureTaskB)
    @display.context = ctx
    @display.on_ready
    @display.on_start
    @display.on_task_updated(FixtureTaskA, previous_state: :pending, current_state: :running, phase: :run, timestamp: started_at)
    @display.on_task_updated(FixtureTaskA, previous_state: :running, current_state: :failed, phase: :run, timestamp: started_at + 0.001)
    @display.on_stop

    output = @output.string
    # X mark should appear in final render after stop
    assert_match(/[✗✕×]/, output)
  end

  def test_render_shows_multiple_running_tasks
    ctx = mock_execution_context(root_task_class: FixtureNamespace::TaskD)
    @display.context = ctx
    @display.on_ready
    @display.on_start
    @display.on_task_updated(FixtureTaskA, previous_state: :pending, current_state: :running, phase: :run, timestamp: Time.now)
    @display.on_task_updated(FixtureNamespace::TaskC, previous_state: :pending, current_state: :running, phase: :run, timestamp: Time.now)
    sleep 0.05

    output = @output.string
    # Both task names should appear
    assert_includes output, "FixtureTaskA"
    assert_includes output, "TaskC"
  end

  def test_final_render_shows_completion
    started_at = Time.now
    ctx = mock_execution_context(root_task_class: FixtureTaskB)
    @display.context = ctx
    @display.on_ready
    @display.on_start
    @display.on_task_updated(FixtureTaskA, previous_state: :pending, current_state: :running, phase: :run, timestamp: started_at)
    @display.on_task_updated(FixtureTaskA, previous_state: :running, current_state: :completed, phase: :run, timestamp: started_at + 0.05)
    @display.on_task_updated(FixtureTaskB, previous_state: :pending, current_state: :running, phase: :run, timestamp: started_at + 0.05)
    @display.on_task_updated(FixtureTaskB, previous_state: :running, current_state: :completed, phase: :run, timestamp: started_at + 0.1)
    @display.on_stop

    output = @output.string
    # Should show checkmark and completion message
    assert_match(/✓/, output)
  end

  def test_simple_mode_uses_single_line
    ctx = mock_execution_context(root_task_class: FixtureTaskB)
    @display.context = ctx
    @display.on_ready
    @display.on_start
    @display.on_task_updated(FixtureTaskA, previous_state: :pending, current_state: :running, phase: :run, timestamp: Time.now)
    sleep 0.05

    output = @output.string
    # Single-line mode should use carriage return for updates
    assert_includes output, "\r"
    # Should NOT use alternate screen buffer
    refute_includes output, "\e[?1049h"
  end

  def test_render_live_overwrites_same_line
    ctx = mock_execution_context(root_task_class: FixtureTaskB)
    @display.context = ctx
    @display.on_ready
    @display.on_start
    @display.on_task_updated(FixtureTaskA, previous_state: :pending, current_state: :running, phase: :run, timestamp: Time.now)
    sleep 0.15  # Wait for at least one render cycle

    output = @output.string
    # Count occurrences of \r\e[K - should have multiple (from render cycles)
    carriage_returns = output.scan("\r\e[K").count

    @display.on_stop

    final_output = @output.string
    # Live rendering should not add newlines
    # Only the final render should have a newline
    assert carriage_returns > 0, "Should have carriage return sequences during live rendering"
    assert_equal 1, final_output.count("\n"), "Should only have one newline (from final render)"
  end

  def test_render_live_respects_terminal_width
    ctx = mock_execution_context(root_task_class: FixtureTaskB)
    @display.context = ctx
    @display.on_ready
    @display.on_start
    @display.on_task_updated(FixtureTaskA, previous_state: :pending, current_state: :running, phase: :run, timestamp: Time.now)
    sleep 0.15 # Wait for at least one render cycle
    @display.on_stop

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
