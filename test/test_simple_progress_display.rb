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

  def test_register_section_impl
    @display.set_root_task(NestedSection)
    @display.register_section_impl(NestedSection, NestedSection::LocalDB)
    # Verify registration was successful (no error raised)
    assert @display.task_registered?(NestedSection)
  end

  def test_register_section_impl_marks_section_as_completed
    @display.set_root_task(NestedSection)
    # Before registration, section should be pending
    assert_equal :pending, @display.task_state(NestedSection)
    @display.register_section_impl(NestedSection, NestedSection::LocalDB)
    # After registration, section itself should be marked as completed
    # (because it's represented by its selected impl)
    assert_equal :completed, @display.task_state(NestedSection)
  end

  def test_register_section_impl_marks_unselected_candidates_as_skipped
    # Use LazyDependencyTest::MySection which references both OptionA and OptionB in impl
    @display.set_root_task(LazyDependencyTest::MySection)
    @display.register_section_impl(
      LazyDependencyTest::MySection,
      LazyDependencyTest::MySection::OptionB
    )
    # Unselected candidate (OptionA) should be marked as skipped
    assert_equal :skipped, @display.task_state(LazyDependencyTest::MySection::OptionA)
    # Selected impl should remain in its current state (pending until actually run)
    assert_equal :pending, @display.task_state(LazyDependencyTest::MySection::OptionB)
  end

  def test_register_section_impl_marks_unselected_candidate_descendants_as_skipped
    # Use LazyDependencyTest::MySection which has:
    # - OptionA (depends on ExpensiveTask)
    # - OptionB (depends on CheapTask)
    @display.set_root_task(LazyDependencyTest::MySection)
    @display.register_section_impl(
      LazyDependencyTest::MySection,
      LazyDependencyTest::MySection::OptionB
    )
    # OptionA's dependency (ExpensiveTask) should also be marked as skipped
    assert_equal :skipped, @display.task_state(LazyDependencyTest::ExpensiveTask)
    # OptionB's dependency (CheapTask) should remain pending (will be executed)
    assert_equal :pending, @display.task_state(LazyDependencyTest::CheapTask)
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

  def test_update_group
    @display.register_task(FixtureTaskA)
    @display.update_group(FixtureTaskA, "test_group", state: :running)
    # Should not raise error
    assert true
  end

  def test_section_completed_without_impl_registration
    @display.set_root_task(NestedSection)
    # Start section without registering impl
    @display.update_task(NestedSection, state: :running)
    @display.update_task(NestedSection, state: :completed)

    # Section should be completed
    assert_equal :completed, @display.task_state(NestedSection)
    # Impl candidates should still be pending (never executed)
    assert_equal :pending, @display.task_state(NestedSection::LocalDB)
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
    assert_match(%r{\[\d+/\d+\]}, output)
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
    sleep 0.15 # Wait for at least one render cycle

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

class TestProgressModeConfiguration < Minitest::Test
  def setup
    Taski.reset_progress_display!
    @original_env = ENV["TASKI_PROGRESS_MODE"]
  end

  def teardown
    Taski.reset_progress_display!
    if @original_env
      ENV["TASKI_PROGRESS_MODE"] = @original_env
    else
      ENV.delete("TASKI_PROGRESS_MODE")
    end
  end

  def test_default_progress_mode_is_tree
    ENV.delete("TASKI_PROGRESS_MODE")
    Taski.reset_progress_display!
    assert_equal :tree, Taski.progress_mode
  end

  def test_progress_mode_can_be_set_to_simple
    Taski.progress_mode = :simple
    assert_equal :simple, Taski.progress_mode
  end

  def test_progress_mode_can_be_set_to_tree
    Taski.progress_mode = :simple
    Taski.progress_mode = :tree
    assert_equal :tree, Taski.progress_mode
  end

  def test_progress_mode_from_environment_variable
    ENV["TASKI_PROGRESS_MODE"] = "simple"
    Taski.reset_progress_display!
    assert_equal :simple, Taski.progress_mode
  end

  def test_progress_mode_from_environment_variable_tree
    ENV["TASKI_PROGRESS_MODE"] = "tree"
    Taski.reset_progress_display!
    assert_equal :tree, Taski.progress_mode
  end

  def test_environment_overrides_api_setting
    ENV["TASKI_PROGRESS_MODE"] = "simple"
    Taski.reset_progress_display!
    Taski.progress_mode = :tree
    # Environment variable takes precedence over code settings
    assert_equal :simple, Taski.progress_mode
  end

  def test_progress_display_returns_tree_display_by_default
    ENV.delete("TASKI_PROGRESS_MODE")
    ENV.delete("TASKI_PROGRESS_DISABLE")
    Taski.reset_progress_display!
    display = Taski.progress_display
    assert_instance_of Taski::Progress::Layout::Tree, display
  end

  def test_progress_display_returns_simple_display_when_mode_is_simple
    ENV.delete("TASKI_PROGRESS_DISABLE")
    Taski.progress_mode = :simple
    display = Taski.progress_display
    assert_instance_of Taski::Progress::Layout::Simple, display
  end

  def test_progress_display_returns_nil_when_disabled
    ENV["TASKI_PROGRESS_DISABLE"] = "1"
    Taski.reset_progress_display!
    assert_nil Taski.progress_display
  end
end
