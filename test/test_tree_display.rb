# frozen_string_literal: true

require "test_helper"
require_relative "fixtures/parallel_tasks"

class TestTreeDisplay < Minitest::Test
  # Remove ANSI color codes for testing
  def strip_ansi(str)
    str.gsub(/\e\[[0-9;]*m/, "")
  end

  def test_tree_method_exists
    assert_respond_to FixtureTaskA, :tree
  end

  def test_tree_returns_string
    result = FixtureTaskA.tree
    assert_kind_of String, result
  end

  def test_tree_includes_task_name
    result = FixtureTaskA.tree
    assert_includes result, "FixtureTaskA"
  end

  def test_tree_shows_simple_dependency
    result = FixtureTaskB.tree
    assert_includes result, "FixtureTaskB"
    assert_includes result, "FixtureTaskA"
  end

  def test_tree_shows_nested_dependencies
    result = FixtureNamespace::TaskD.tree
    assert_includes result, "FixtureNamespace::TaskD"
    assert_includes result, "FixtureNamespace::TaskC"
    assert_includes result, "FixtureTaskA"
  end

  def test_tree_shows_deep_dependencies
    result = DeepDependency::Nested::TaskH.tree
    assert_includes result, "DeepDependency::Nested::TaskH"
    assert_includes result, "DeepDependency::Nested::TaskG"
    assert_includes result, "DeepDependency::TaskE"
    assert_includes result, "DeepDependency::TaskF"
    assert_includes result, "DeepDependency::TaskD"
    assert_includes result, "ParallelTaskC"
  end

  def test_tree_shows_type_label_for_task
    result = FixtureTaskA.tree
    assert_includes result, "(Task)"
  end

  def test_tree_shows_type_label_for_section
    result = NestedSection.tree
    assert_includes result, "(Section)"
  end

  # Section.impl candidates ARE shown in tree display for visualization purposes
  # even though they are resolved at runtime for execution
  def test_tree_shows_impl_prefix_for_section_dependency
    result = NestedSection.tree
    assert_includes result, "[impl]"
    assert_includes result, "NestedSection::LocalDB"
  end

  def test_tree_shows_nested_section_with_impl
    result = strip_ansi(OuterSection.tree)
    assert_includes result, "OuterSection (Section)"
    assert_includes result, "[impl]"
    assert_includes result, "InnerSection (Section)"
    assert_includes result, "InnerSection::InnerImpl (Task)"
  end

  def test_tree_shows_mixed_task_and_section_dependencies
    result = strip_ansi(DeepDependency::TaskD.tree)
    assert_includes result, "DeepDependency::TaskD (Task)"
    assert_includes result, "ParallelTaskC (Task)"
    assert_includes result, "ParallelSection (Section)"
    # ParallelSectionImpl2 is not a nested class of ParallelSection,
    # so it should NOT have [impl] label (only nested classes get [impl])
    assert_includes result, "ParallelSectionImpl2 (Task)"
    refute_includes result, "[impl] ParallelSectionImpl2"
  end

  def test_tree_includes_ansi_color_codes
    result = FixtureTaskA.tree
    # Check that ANSI codes are present
    assert_match(/\e\[/, result)
  end

  def test_tree_shows_task_numbers
    result = strip_ansi(FixtureTaskB.tree)
    assert_match(/\[1\].*FixtureTaskB/, result)
    assert_match(/\[2\].*FixtureTaskA/, result)
  end

  def test_tree_same_task_has_same_number
    result = strip_ansi(DeepDependency::Nested::TaskH.tree)
    # Find all occurrences of ParallelTaskA with their numbers
    matches = result.scan(/\[(\d+)\].*ParallelTaskA/)
    assert matches.size >= 2, "ParallelTaskA should appear multiple times"
    # All occurrences should have the same number
    numbers = matches.flatten.uniq
    assert_equal 1, numbers.size, "Same task should have the same number"
  end

  def test_tree_expands_duplicate_dependencies
    result = strip_ansi(DeepDependency::Nested::TaskH.tree)
    # ParallelSection appears multiple times and should be fully expanded each time
    # Count how many times ParallelSectionImpl2 appears (it's a dependency of ParallelSection)
    impl_count = result.scan("ParallelSectionImpl2").size
    assert impl_count >= 2, "ParallelSectionImpl2 should appear multiple times as ParallelSection is fully expanded"
  end

  def test_tree_shows_circular_marker_for_circular_dependency
    require_relative "fixtures/circular_tasks"
    result = strip_ansi(CircularTaskA.tree)
    assert_includes result, "CircularTaskA"
    assert_includes result, "CircularTaskB"
    assert_includes result, "(circular)"
  end

  def test_tree_shows_circular_marker_for_indirect_circular_dependency
    require_relative "fixtures/circular_tasks"
    result = strip_ansi(IndirectCircular::TaskX.tree)
    assert_includes result, "IndirectCircular::TaskX"
    assert_includes result, "IndirectCircular::TaskY"
    assert_includes result, "IndirectCircular::TaskZ"
    assert_includes result, "(circular)"
  end
end

# Tests for TreeProgressDisplay class (dynamic progress display)
class TestTreeProgressDisplay < Minitest::Test
  def setup
    Taski.reset_global_registry!
    Taski.reset_progress_display!
    @output = StringIO.new
    @display = Taski::Execution::TreeProgressDisplay.new(output: @output)
  end

  def teardown
    Taski.reset_global_registry!
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

  def test_start_and_stop_without_tty
    # When output is not a TTY, start should do nothing
    @display.start
    @display.stop
    # No error should be raised
    assert true
  end

  def test_nested_start_stop_calls
    # Multiple start/stop calls should be properly nested
    @display.start
    @display.start
    @display.stop
    @display.stop
    # No error should be raised
    assert true
  end

  def test_section_class_helper
    assert Taski::Execution::TreeProgressDisplay.section_class?(NestedSection)
    refute Taski::Execution::TreeProgressDisplay.section_class?(FixtureTaskA)
  end

  def test_nested_class_helper
    assert Taski::Execution::TreeProgressDisplay.nested_class?(NestedSection::LocalDB, NestedSection)
    refute Taski::Execution::TreeProgressDisplay.nested_class?(FixtureTaskA, NestedSection)
  end

  def test_set_output_capture
    capture = Taski::Execution::TaskOutputRouter.new(StringIO.new)
    @display.set_output_capture(capture)
    # Verify no error is raised and capture is accepted
    assert true
  end

  def test_set_output_capture_with_nil
    @display.set_output_capture(nil)
    # Should accept nil without error
    assert true
  end
end

# Tests for TreeProgressDisplay with TTY-like output
class TestTreeProgressDisplayWithTTY < Minitest::Test
  # Custom StringIO that pretends to be a TTY for testing
  class TTYStringIO < StringIO
    def tty?
      true
    end
  end

  def setup
    Taski.reset_global_registry!
    Taski.reset_progress_display!
    @output = TTYStringIO.new
    @display = Taski::Execution::TreeProgressDisplay.new(output: @output)
  end

  def teardown
    @display&.stop
    Taski.reset_global_registry!
    Taski.reset_progress_display!
  end

  def test_start_with_tty_starts_renderer_thread
    @display.set_root_task(FixtureTaskA)
    @display.start
    # Give the renderer thread a moment to run
    sleep 0.15
    @display.stop

    output = @output.string
    # Should contain ANSI escape codes for cursor control
    assert_match(/\e\[/, output)
  end

  def test_render_shows_task_progress
    @display.set_root_task(FixtureTaskB)
    @display.start
    @display.update_task(FixtureTaskA, state: :running)
    sleep 0.15
    @display.update_task(FixtureTaskA, state: :completed, duration: 50)
    sleep 0.15
    @display.stop

    output = @output.string
    # Should contain task names
    assert_includes output, "FixtureTaskB"
    assert_includes output, "FixtureTaskA"
  end

  def test_render_shows_section_with_impl
    @display.set_root_task(NestedSection)
    @display.register_section_impl(NestedSection, NestedSection::LocalDB)
    @display.start
    sleep 0.15
    @display.stop

    output = @output.string
    assert_includes output, "NestedSection"
    assert_includes output, "LocalDB"
  end

  def test_render_shows_spinner_for_running_task
    @display.set_root_task(FixtureTaskA)
    @display.start
    @display.update_task(FixtureTaskA, state: :running)
    sleep 0.15
    @display.stop

    output = @output.string
    # Should contain one of the spinner characters
    spinner_chars = %w[⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏]
    has_spinner = spinner_chars.any? { |char| output.include?(char) }
    assert has_spinner, "Output should contain a spinner character"
  end

  def test_render_shows_checkmark_for_completed_task
    @display.set_root_task(FixtureTaskA)
    @display.start
    @display.update_task(FixtureTaskA, state: :running)
    @display.update_task(FixtureTaskA, state: :completed, duration: 100)
    sleep 0.15
    @display.stop

    output = @output.string
    assert_includes output, "✓"
  end

  def test_render_shows_x_for_failed_task
    @display.set_root_task(FixtureTaskA)
    @display.start
    @display.update_task(FixtureTaskA, state: :running)
    @display.update_task(FixtureTaskA, state: :failed, error: StandardError.new("test"))
    sleep 0.15
    @display.stop

    output = @output.string
    assert_includes output, "✗"
  end

  def test_render_shows_duration_for_completed_task
    @display.set_root_task(FixtureTaskA)
    @display.start
    @display.update_task(FixtureTaskA, state: :running)
    @display.update_task(FixtureTaskA, state: :completed, duration: 150)
    sleep 0.15
    @display.stop

    output = @output.string
    assert_includes output, "150ms"
  end

  def test_render_shows_unselected_impl_as_dimmed
    # Use LazyDependencyTest::MySection which has both OptionA and OptionB detected by static analysis
    @display.set_root_task(LazyDependencyTest::MySection)
    # Register OptionB as selected, so OptionA should be unselected
    @display.register_section_impl(LazyDependencyTest::MySection, LazyDependencyTest::MySection::OptionB)
    @display.start
    sleep 0.15
    @display.stop

    output = @output.string
    # OptionA should be in the output (as unselected)
    assert_includes output, "OptionA"
    # OptionB should also be in the output (as selected)
    assert_includes output, "OptionB"
    # Should have the skipped icon for unselected impl
    assert_includes output, "⊘"
  end

  def test_render_final_clears_and_reprints
    @display.set_root_task(FixtureTaskA)
    @display.start
    @display.update_task(FixtureTaskA, state: :completed, duration: 100)
    sleep 0.15
    @display.stop

    output = @output.string
    # Should contain cursor hide and show sequences
    assert_includes output, "\e[?25l" # Hide cursor
    assert_includes output, "\e[?25h" # Show cursor
  end

  def test_deep_dependency_tree_rendering
    @display.set_root_task(FixtureNamespace::TaskD)
    @display.start
    sleep 0.15
    @display.stop

    output = @output.string
    # Should show all tasks in the tree
    assert_includes output, "TaskD"
    assert_includes output, "TaskC"
    assert_includes output, "FixtureTaskA"
    # Should have tree connectors
    assert_match(/[├└]/, output)
  end

  def test_hides_and_shows_cursor
    @display.set_root_task(FixtureTaskA)
    @display.start
    sleep 0.05
    @display.stop

    output = @output.string
    # Should hide cursor on start and show on stop
    assert_includes output, "\e[?25l", "Should hide cursor"
    assert_includes output, "\e[?25h", "Should show cursor"
  end

  def test_very_deep_dependency_tree_with_state_updates
    # Test with a very deep dependency tree (DeepDependency::Nested::TaskH)
    @display.set_root_task(DeepDependency::Nested::TaskH)
    @display.start
    # Update multiple tasks to simulate execution
    @display.update_task(DeepDependency::TaskD, state: :running)
    @display.update_task(ParallelTaskC, state: :running)
    sleep 0.15
    @display.update_task(DeepDependency::TaskD, state: :completed, duration: 50)
    @display.update_task(ParallelTaskC, state: :completed, duration: 60)
    sleep 0.15
    @display.stop

    output = @output.string
    # Should contain all tasks in the deep tree
    assert_includes output, "TaskH"
    assert_includes output, "TaskG"
    assert_includes output, "TaskE"
    assert_includes output, "TaskF"
    assert_includes output, "TaskD"
    assert_includes output, "ParallelTaskC"
  end

  def test_render_with_output_capture
    # Create a mock output capture that returns a last line
    output_capture = Taski::Execution::TaskOutputRouter.new(StringIO.new)

    @display.set_root_task(FixtureTaskA)
    @display.set_output_capture(output_capture)

    # Simulate output capture in a thread
    thread = Thread.new do
      output_capture.start_capture(FixtureTaskA)
      output_capture.puts("Processing data...")
      sleep 0.2
      output_capture.stop_capture
    end

    @display.start
    @display.update_task(FixtureTaskA, state: :running)
    sleep 0.15
    thread.join
    @display.update_task(FixtureTaskA, state: :completed, duration: 100)
    @display.stop

    output = @output.string
    # Should include the task name
    assert_includes output, "FixtureTaskA"
  end

  def test_task_output_suffix_with_running_task_and_capture
    # Custom TTY output with winsize
    tty_output = TTYStringIO.new
    def tty_output.winsize
      [24, 120]
    end

    display = Taski::Execution::TreeProgressDisplay.new(output: tty_output)
    output_capture = Taski::Execution::TaskOutputRouter.new(StringIO.new)

    display.set_root_task(FixtureTaskA)
    display.set_output_capture(output_capture)

    # Capture some output
    output_capture.start_capture(FixtureTaskA)
    output_capture.puts("Working on step 1...")
    output_capture.stop_capture

    display.start
    display.update_task(FixtureTaskA, state: :running)
    sleep 0.15
    display.stop

    output = tty_output.string
    # The output should show some indication of the task
    assert_includes output, "FixtureTaskA"
  end

  def test_task_output_truncation_with_long_output
    # Output with narrow width to trigger truncation
    tty_output = TTYStringIO.new
    def tty_output.winsize
      [24, 80]  # Narrow terminal
    end

    display = Taski::Execution::TreeProgressDisplay.new(output: tty_output)
    output_capture = Taski::Execution::TaskOutputRouter.new(StringIO.new)

    display.set_root_task(FixtureTaskA)
    display.set_output_capture(output_capture)

    # Capture very long output
    output_capture.start_capture(FixtureTaskA)
    output_capture.puts("This is a very long output line that should definitely be truncated when displayed inline next to the task name")
    output_capture.stop_capture

    display.start
    display.update_task(FixtureTaskA, state: :running)
    sleep 0.15
    display.stop

    output = tty_output.string
    assert_includes output, "FixtureTaskA"
  end

  def test_terminal_width_without_winsize
    # Output without winsize method
    output_without_winsize = TTYStringIO.new

    display = Taski::Execution::TreeProgressDisplay.new(output: output_without_winsize)
    display.set_root_task(FixtureTaskA)
    display.start
    sleep 0.15
    display.stop

    # Should not raise error, uses default width
    output = output_without_winsize.string
    assert_includes output, "FixtureTaskA"
  end

  def test_terminal_width_returns_nil_from_winsize
    # Output where winsize returns nil values
    tty_output = TTYStringIO.new
    def tty_output.winsize
      [nil, nil]
    end

    display = Taski::Execution::TreeProgressDisplay.new(output: tty_output)
    display.set_root_task(FixtureTaskA)
    display.start
    sleep 0.15
    display.stop

    # Should use default width of 80
    output = tty_output.string
    assert_includes output, "FixtureTaskA"
  end
end

# Tests for TaskOutputRouter class (pipe-based output capture)
class TestTaskOutputRouter < Minitest::Test
  def setup
    @original = StringIO.new
    @router = Taski::Execution::TaskOutputRouter.new(@original)
  end

  def teardown
    @router.close_all
  end

  def test_write_passes_through_when_not_capturing
    @router.write("hello")
    assert_equal "hello", @original.string
  end

  def test_write_suppresses_output_when_capturing
    @router.start_capture(FixtureTaskA)
    @router.write("hello")
    @router.stop_capture
    # Output should be suppressed (not written to original)
    assert_equal "", @original.string
  end

  def test_puts_passes_through_when_not_capturing
    @router.puts("hello")
    assert_equal "hello\n", @original.string
  end

  def test_puts_suppresses_output_when_capturing
    @router.start_capture(FixtureTaskA)
    @router.puts("hello")
    @router.stop_capture
    # Output should be suppressed (not written to original)
    assert_equal "", @original.string
  end

  def test_start_and_stop_capture
    @router.start_capture(FixtureTaskA)
    @router.write("test output")
    @router.stop_capture
    # Pipe-based capture does not return captured content
    # Instead, poll and check last_line_for
    @router.poll
    assert_equal "test output", @router.last_line_for(FixtureTaskA)
  end

  def test_last_line_for_returns_captured_line
    @router.start_capture(FixtureTaskA)
    @router.puts("line 1")
    @router.puts("line 2")
    @router.puts("line 3")
    @router.stop_capture
    @router.poll

    assert_equal "line 3", @router.last_line_for(FixtureTaskA)
  end

  def test_last_line_for_returns_nil_for_unknown_task
    assert_nil @router.last_line_for(FixtureTaskA)
  end

  def test_last_line_updates_after_poll
    @router.start_capture(FixtureTaskA)
    @router.puts("first line")
    @router.poll
    assert_equal "first line", @router.last_line_for(FixtureTaskA)

    @router.puts("second line")
    @router.poll
    assert_equal "second line", @router.last_line_for(FixtureTaskA)

    @router.stop_capture
  end

  def test_multiple_threads_capture_independently
    results = {}
    threads = 2.times.map do |i|
      task = (i == 0) ? FixtureTaskA : FixtureTaskB
      Thread.new do
        @router.start_capture(task)
        @router.puts("output from thread #{i}")
        @router.stop_capture
      end
    end
    threads.each(&:join)
    @router.poll

    results[FixtureTaskA] = @router.last_line_for(FixtureTaskA)
    results[FixtureTaskB] = @router.last_line_for(FixtureTaskB)

    assert_equal "output from thread 0", results[FixtureTaskA]
    assert_equal "output from thread 1", results[FixtureTaskB]
  end

  def test_tty_delegation
    tty_io = StringIO.new
    def tty_io.tty?
      true
    end

    router = Taski::Execution::TaskOutputRouter.new(tty_io)
    assert router.tty?
    router.close_all
  end

  def test_flush_delegation
    @router.flush
    # Should not raise error
    assert true
  end

  def test_puts_with_no_args
    @router.puts
    assert_equal "\n", @original.string
  end

  def test_puts_with_no_args_when_capturing
    @router.start_capture(FixtureTaskA)
    @router.puts
    @router.stop_capture
    # Newline only is not captured as last_line (whitespace is ignored)
    assert_equal "", @original.string
  end

  def test_print_method
    @router.print("hello", " ", "world")
    assert_equal "hello world", @original.string
  end

  def test_print_method_when_capturing
    @router.start_capture(FixtureTaskA)
    @router.print("hello", " ", "world")
    @router.stop_capture
    @router.poll
    assert_equal "hello world", @router.last_line_for(FixtureTaskA)
    assert_equal "", @original.string
  end

  def test_append_operator
    @router << "hello"
    assert_equal "hello", @original.string
  end

  def test_append_operator_when_capturing
    @router.start_capture(FixtureTaskA)
    @router << "hello"
    @router.stop_capture
    @router.poll
    assert_equal "hello", @router.last_line_for(FixtureTaskA)
    assert_equal "", @original.string
  end

  def test_append_operator_returns_self
    result = @router << "test"
    assert_same @router, result
  end

  def test_isatty_delegation
    tty_io = StringIO.new
    def tty_io.isatty
      true
    end

    router = Taski::Execution::TaskOutputRouter.new(tty_io)
    assert router.isatty
    router.close_all
  end

  def test_winsize_delegation
    io_with_winsize = StringIO.new
    def io_with_winsize.winsize
      [24, 80]
    end

    router = Taski::Execution::TaskOutputRouter.new(io_with_winsize)
    assert_equal [24, 80], router.winsize
    router.close_all
  end

  def test_method_missing_delegation
    io = StringIO.new
    def io.custom_method
      "custom_result"
    end

    router = Taski::Execution::TaskOutputRouter.new(io)
    assert_equal "custom_result", router.custom_method
    router.close_all
  end

  def test_respond_to_missing
    io = StringIO.new
    def io.custom_method
      "custom_result"
    end

    router = Taski::Execution::TaskOutputRouter.new(io)
    assert router.respond_to?(:custom_method)
    refute router.respond_to?(:nonexistent_method)
    router.close_all
  end

  def test_extract_last_line_with_only_whitespace
    @router.start_capture(FixtureTaskA)
    @router.puts("   ")
    @router.puts("   ")
    @router.stop_capture
    @router.poll

    # When all lines are whitespace only, last_line should be nil
    assert_nil @router.last_line_for(FixtureTaskA)
  end

  def test_extract_last_line_with_trailing_empty_lines
    @router.start_capture(FixtureTaskA)
    @router.puts("actual content")
    @router.puts("")
    @router.puts("")
    @router.stop_capture
    @router.poll

    assert_equal "actual content", @router.last_line_for(FixtureTaskA)
  end

  def test_active_returns_true_when_pipes_open
    @router.start_capture(FixtureTaskA)
    @router.puts("test")
    @router.stop_capture
    # Read pipe should still be open until poll reads and EOF
    assert @router.active?
    @router.poll
  end

  def test_close_all_cleans_up_resources
    @router.start_capture(FixtureTaskA)
    @router.puts("test")
    @router.stop_capture
    @router.close_all
    refute @router.active?
  end
end
