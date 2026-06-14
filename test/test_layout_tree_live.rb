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

  # @last_line_count must reset when an execution stops, so the next top-level
  # execution's first live frame does not move the cursor up and erase the
  # previous execution's final output (clear_previous_output keys off it).
  def test_last_line_count_is_reset_after_an_execution_stops
    parent = stub_task_class_with_deps("Parent", [stub_task_class("A"), stub_task_class("B")])
    @layout.context = mock_execution_facade(root_task_class: parent)
    @layout.on_ready
    @layout.on_start
    # Simulate the render loop having drawn a multi-line frame, so the reset is
    # actually exercised (otherwise @last_line_count is already 0 and the test
    # is vacuous).
    @layout.instance_variable_set(:@last_line_count, 5)
    @layout.on_stop

    assert_equal 0, @layout.instance_variable_get(:@last_line_count),
      "the next execution's first frame must not erase the previous execution's final output"
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

  # ========================================
  # Render-thread death must not leak resources
  # ========================================
  # If the terminal goes away mid-run (IOError/EPIPE in the render loop), the
  # render thread dies with that exception. Thread#join re-raises it, which
  # used to abort handle_stop BEFORE stop_spinner_timer and the cursor
  # restore — leaking a perpetually-waking spinner thread and leaving the
  # user's cursor hidden.

  # A TTY-like output that starts failing after a given number of writes,
  # optionally healing afterwards. Records every attempted write.
  class FlakyOutput
    attr_reader :writes

    def initialize(fail_on: nil, fail_count: 1_000_000)
      @writes = []
      @count = 0
      @fail_on = fail_on
      @failures_left = fail_count
    end

    def record(str)
      @writes << str.to_s
      @count += 1
      if @fail_on && @count >= @fail_on && @failures_left > 0
        @failures_left -= 1
        raise IOError, "stream closed"
      end
    end

    def print(*args) = args.each { |a| record(a) }

    def puts(*args) = (args.empty? ? record("\n") : args.each { |a| record(a) })

    def write(*args) = args.each { |a| record(a) }

    def flush
    end

    def tty? = true

    def winsize = [24, 80]
  end

  def test_render_thread_death_does_not_leak_the_spinner_thread
    # The hide-cursor write succeeds; everything after (the render loop's
    # writes) raises permanently — the terminal died mid-run.
    output = FlakyOutput.new(fail_on: 2)
    layout = Taski::Progress::Layout::Tree::Live.new(output: output)
    layout.context = mock_execution_facade(root_task_class: stub_task_class("DyingTTY"))
    layout.on_ready
    layout.on_start
    sleep 0.25 # let the render thread wake and die on the dead output

    layout.on_stop # must not raise (join used to re-raise the IOError)

    timer = layout.instance_variable_get(:@spinner_timer)
    refute layout.instance_variable_get(:@spinner_running),
      "spinner must be stopped even when the render thread died"
    refute timer&.alive?, "spinner thread must not keep waking forever"
  end

  def test_cursor_restore_is_attempted_after_render_thread_death
    # Fail exactly once (killing the render thread), then heal — the terminal
    # came back, so the cursor restore must reach it.
    output = FlakyOutput.new(fail_on: 2, fail_count: 1)
    layout = Taski::Progress::Layout::Tree::Live.new(output: output)
    layout.context = mock_execution_facade(root_task_class: stub_task_class("FlakyTTY"))
    layout.on_ready
    layout.on_start
    sleep 0.25

    layout.on_stop

    assert_includes output.writes, "\e[?25h",
      "the cursor must be restored once the output is writable again"
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
