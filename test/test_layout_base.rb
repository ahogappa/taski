# frozen_string_literal: true

require "test_helper"
require "stringio"
require "taski/progress/theme/base"
require "taski/progress/theme/default"
require "taski/progress/theme/compact"
require "taski/progress/layout/base"

class TestLayoutBase < Minitest::Test
  include TaskiTestHelper

  def setup
    @output = StringIO.new
    @layout = Taski::Progress::Layout::Base.new(output: @output)
  end

  # The spinner timer thread must not die from a divide-by-zero when a custom
  # theme returns no spinner frames.
  def test_spinner_timer_survives_empty_spinner_frames
    theme = Class.new(Taski::Progress::Theme::Base) do
      def spinner_frames
        []
      end

      def spinner_interval
        0.01
      end
    end.new
    layout = Taski::Progress::Layout::Base.new(output: StringIO.new, theme: theme)

    layout.send(:start_spinner_timer)
    sleep 0.05
    timer = layout.instance_variable_get(:@spinner_timer)

    assert timer.alive?, "spinner timer thread died (divide by zero on empty frames)"
  ensure
    layout&.send(:stop_spinner_timer)
  end

  # A raising theme method must not raise out of render_theme (which would
  # silently kill the background render thread). It should degrade to an empty
  # string instead. Themes are not Tasks, so inline Class.new is fine here.
  def test_render_theme_isolates_raising_theme
    theme = Class.new(Taski::Progress::Theme::Base) do
      def task_start(task:, execution: nil)
        raise "boom in theme"
      end
    end.new
    layout = Taski::Progress::Layout::Base.new(output: StringIO.new, theme: theme)

    result = layout.send(:render_theme, :task_start, task: Taski::Progress::TaskInfo.new(name: "T"))

    assert_equal "", result
  end

  # A typo'd field access (TaskInfo raises NoMethodError for unknown members,
  # unlike the old drops' silent nil) must also degrade to "" — loud in logs,
  # safe on screen.
  def test_render_theme_isolates_typoed_field_access
    theme = Class.new(Taski::Progress::Theme::Base) do
      def task_start(task:, execution: nil)
        "Starting #{task.nmae}"
      end
    end.new
    layout = Taski::Progress::Layout::Base.new(output: StringIO.new, theme: theme)

    result = layout.send(:render_theme, :task_start, task: Taski::Progress::TaskInfo.new(name: "T"))

    assert_equal "", result
  end

  # An old-style zero-arg override (pre-replacement signature) receives the
  # task:/execution: keywords and raises ArgumentError — contained the same way.
  def test_render_theme_isolates_wrong_arity_override
    theme = Class.new(Taski::Progress::Theme::Base) do
      def task_start
        "old-style template"
      end
    end.new
    layout = Taski::Progress::Layout::Base.new(output: StringIO.new, theme: theme)

    result = layout.send(:render_theme, :task_start, task: Taski::Progress::TaskInfo.new(name: "T"))

    assert_equal "", result
  end

  # A theme failure must log a distinct TEMPLATE_ERROR event rather than
  # reusing OBSERVER_ERROR, so a broken theme can be told apart from an
  # observer-callback crash when filtering logs.
  def test_theme_failure_logs_template_error_not_observer_error
    require "logger"
    log_output = StringIO.new
    original_logger = Taski.logger
    Taski.logger = Logger.new(log_output)

    theme = Class.new(Taski::Progress::Theme::Base) do
      def task_start(task:, execution: nil)
        raise "boom in theme"
      end
    end.new
    layout = Taski::Progress::Layout::Base.new(output: StringIO.new, theme: theme)
    layout.send(:render_theme, :task_start, task: Taski::Progress::TaskInfo.new(name: "T"))

    assert_match(/template\.render_error/, log_output.string)
    refute_match(/observer\.error/, log_output.string)
  ensure
    Taski.logger = original_logger
  end

  # End to end through the background render path: a raising theme must leave
  # the render thread alive (an escaped exception would freeze the display).
  def test_render_loop_survives_raising_theme
    theme = Class.new(Taski::Progress::Theme::Base) do
      def task_start(task:, execution: nil)
        raise "boom in theme"
      end

      def render_interval = 0.01
    end.new
    layout = Taski::Progress::Layout::Base.new(output: StringIO.new, theme: theme)
    task_class = Class.new

    layout.send(:render_loop) { layout.send(:render_task_started, task_class) }
    sleep 0.05
    thread = layout.instance_variable_get(:@render_thread)

    assert thread.alive?, "render thread died — theme exception escaped render_theme"
  ensure
    layout&.send(:stop_render_loop)
  end

  # === Inheritance tests ===

  def test_inherits_from_task_observer
    assert_kind_of Taski::Execution::TaskObserver, @layout
  end

  # === Observer interface tests ===

  def test_responds_to_observer_interface
    assert_respond_to @layout, :on_ready
    assert_respond_to @layout, :on_start
    assert_respond_to @layout, :on_stop
    assert_respond_to @layout, :on_task_updated
    assert_respond_to @layout, :on_group_started
    assert_respond_to @layout, :on_group_completed
    assert_respond_to @layout, :queue_message
  end

  # === Task registration via on_task_updated ===

  def test_on_task_updated_registers_task
    task_class = Class.new
    @layout.on_task_updated(task_class, previous_state: nil, current_state: :pending, phase: :run, timestamp: Time.now)
    assert @layout.task_registered?(task_class)
  end

  def test_on_task_updated_pending_is_idempotent
    task_class = Class.new
    now = Time.now
    @layout.on_task_updated(task_class, previous_state: nil, current_state: :pending, phase: :run, timestamp: now)
    @layout.on_task_updated(task_class, previous_state: nil, current_state: :pending, phase: :run, timestamp: now)
    # No error raised
  end

  # === Task state management ===

  def test_on_task_updated_running_changes_state
    task_class = Class.new
    now = Time.now
    @layout.on_task_updated(task_class, previous_state: nil, current_state: :pending, phase: :run, timestamp: now)
    @layout.on_task_updated(task_class, previous_state: :pending, current_state: :running, phase: :run, timestamp: now)
    assert_equal :running, @layout.task_state(task_class)
  end

  def test_on_task_updated_completed_changes_state
    task_class = Class.new
    started = Time.now
    @layout.on_task_updated(task_class, previous_state: nil, current_state: :pending, phase: :run, timestamp: started)
    @layout.on_task_updated(task_class, previous_state: :pending, current_state: :running, phase: :run, timestamp: started)
    @layout.on_task_updated(task_class, previous_state: :running, current_state: :completed, phase: :run, timestamp: started + 0.1234)
    assert_equal :completed, @layout.task_state(task_class)
  end

  def test_on_task_updated_failed_changes_state
    task_class = Class.new
    now = Time.now
    @layout.on_task_updated(task_class, previous_state: nil, current_state: :pending, phase: :run, timestamp: now)
    @layout.on_task_updated(task_class, previous_state: :pending, current_state: :running, phase: :run, timestamp: now)
    @layout.on_task_updated(task_class, previous_state: :running, current_state: :failed, phase: :run, timestamp: now + 1)
    assert_equal :failed, @layout.task_state(task_class)
  end

  def test_on_task_updated_auto_registers
    task_class = Class.new
    @layout.on_task_updated(task_class, previous_state: :pending, current_state: :running, phase: :run, timestamp: Time.now)
    assert @layout.task_registered?(task_class)
  end

  # === Clean state management ===

  def test_on_task_updated_clean_running_state
    task_class = Class.new
    now = Time.now
    @layout.on_task_updated(task_class, previous_state: nil, current_state: :pending, phase: :run, timestamp: now)
    @layout.on_task_updated(task_class, previous_state: :pending, current_state: :completed, phase: :run, timestamp: now + 1)
    @layout.on_task_updated(task_class, previous_state: :pending, current_state: :running, phase: :clean, timestamp: now + 2)
    assert_equal :running, @layout.task_state(task_class)
  end

  def test_on_task_updated_clean_completed_state
    task_class = Class.new
    now = Time.now
    @layout.on_task_updated(task_class, previous_state: nil, current_state: :pending, phase: :run, timestamp: now)
    @layout.on_task_updated(task_class, previous_state: :pending, current_state: :completed, phase: :run, timestamp: now + 1)
    @layout.on_task_updated(task_class, previous_state: :pending, current_state: :running, phase: :clean, timestamp: now + 2)
    @layout.on_task_updated(task_class, previous_state: :running, current_state: :completed, phase: :clean, timestamp: now + 3)
    assert_equal :completed, @layout.task_state(task_class)
  end

  # === Nest level management ===

  def test_on_start_and_on_stop_manage_nest_level
    @layout.on_start
    @layout.on_start # nested executor opens a second level
    @layout.queue_message("queued-marker")

    @layout.on_stop # inner stop: must NOT finalize or flush
    refute_includes @output.string, "queued-marker",
      "messages must not flush while a nested execution is still open"

    @layout.on_stop # outer stop: finalizes and flushes the queue
    assert_includes @output.string, "queued-marker"
  end

  def test_on_stop_without_on_start_does_not_crash
    @layout.on_stop
    # No error raised
  end

  # === Root task via on_ready ===

  def test_on_ready_sets_root_task_from_context
    @layout.context = mock_execution_facade(root_task_class: String)
    @layout.on_ready
    @layout.on_start
    assert_includes @output.string, "String"
  end

  # A nested executor readies on its own facade WHILE an execution is active
  # (@nest_level > 0). It must not overwrite the displayed root or rebuild the
  # tree.
  def test_nested_on_ready_does_not_overwrite_root
    @layout.context = mock_execution_facade(root_task_class: String)
    @layout.on_ready
    @layout.on_start # now inside an execution (@nest_level == 1)

    @layout.context = mock_execution_facade(root_task_class: Integer)
    @layout.on_ready # nested ready on a different facade

    assert_equal String, @layout.instance_variable_get(:@root_task_class)
  end

  # When the outermost execution stops, per-execution state is cleared so the
  # display does not carry the root/tasks/spinner into the next top-level
  # execution.
  def test_on_stop_clears_per_execution_state
    @layout.context = stub_facade(root: String, capture: :cap_a)
    @layout.on_ready
    @layout.on_start
    leftover = Class.new
    @layout.on_task_updated(leftover, previous_state: nil, current_state: :pending, phase: :run, timestamp: Time.now)
    assert @layout.task_registered?(leftover)
    @layout.instance_variable_set(:@spinner_index, 7)

    @layout.on_stop

    assert_nil @layout.instance_variable_get(:@root_task_class)
    assert_nil current_output_capture
    refute @layout.task_registered?(leftover)
    assert_equal 0, @layout.spinner_index,
      "the spinner animation must restart from frame 0 for the next execution"
  end

  # The reset runs in an ensure, so a raising final render (e.g. a broken
  # terminal) still clears state — otherwise (dispatch swallows observer
  # errors) a failed render would silently leak this run's root + task count
  # into the next top-level execution.
  def test_on_stop_resets_even_when_the_final_render_raises
    layout = Taski::Progress::Layout::Base.new(output: @output)
    layout.context = stub_facade(root: String, capture: :cap_a)
    layout.on_ready
    layout.on_start
    tc = Class.new
    layout.on_task_updated(tc, previous_state: nil, current_state: :pending, phase: :run, timestamp: Time.now)
    def layout.handle_stop = raise("render boom") # final render fails

    assert_raises(RuntimeError) { layout.on_stop }

    assert_nil layout.instance_variable_get(:@root_task_class),
      "reset must run from the ensure even when the final render raises"
    refute layout.task_registered?(tc)
  end

  # After the first execution stops, a second top-level execution adopts its
  # own root + capture (the cleared state makes on_ready take the fresh-adopt
  # path).
  def test_second_top_level_execution_adopts_its_own_state
    @layout.context = stub_facade(root: String, capture: :cap_a)
    @layout.on_ready
    @layout.on_start
    @layout.on_stop # first execution fully finishes — state cleared

    @layout.context = stub_facade(root: Integer, capture: :cap_b)
    @layout.on_ready

    assert_equal Integer, @layout.instance_variable_get(:@root_task_class)
    assert_equal :cap_b, current_output_capture
  end

  # run_and_clean calls notify_start (raising nest level) BEFORE its first
  # on_ready, so a second run_and_clean readies at nest_level 1 — it must still
  # adopt its own state, because the reset already happened when the first
  # execution stopped (not lazily at on_ready).
  def test_second_execution_adopts_even_when_readying_at_raised_nest_level
    @layout.context = stub_facade(root: String, capture: :cap_a)
    @layout.on_ready
    @layout.on_start
    @layout.on_stop # first execution finished — state cleared

    @layout.on_start # run_and_clean's pre-increment, before its first on_ready
    @layout.context = stub_facade(root: Integer, capture: :cap_b)
    @layout.on_ready

    assert_equal Integer, @layout.instance_variable_get(:@root_task_class)
    assert_equal :cap_b, current_output_capture
  ensure
    @layout.on_stop
  end

  # The clean phase of run_and_clean re-readies on the SAME facade after it
  # tore down the run-phase output router and built a fresh one. The layout
  # must re-adopt the fresh router, or the status line keeps reading the dead
  # run-phase router during clean (showing stale/blank output).
  def test_on_ready_readopts_capture_when_same_facade_re_readies
    facade = stub_facade(root: String, capture: :run_router)
    @layout.context = facade
    @layout.on_ready
    assert_equal :run_router, current_output_capture

    facade.define_singleton_method(:output_capture) { :clean_router }
    @layout.on_ready

    assert_equal :clean_router, current_output_capture,
      "the fresh clean-phase router must be re-adopted"
    assert_equal String, @layout.instance_variable_get(:@root_task_class),
      "the root task must not change across phases"
  end

  # A nested execution on a DIFFERENT facade (active execution, @nest_level > 0)
  # does not own the display, so it must not retarget the capture nor overwrite
  # the root.
  def test_on_ready_does_not_retarget_capture_for_a_nested_different_facade
    @layout.context = stub_facade(root: String, capture: :run_router)
    @layout.on_ready
    @layout.on_start # inside an execution (@nest_level == 1)

    @layout.context = stub_facade(root: Integer, capture: :nested_router)
    @layout.on_ready

    assert_equal :run_router, current_output_capture,
      "a nested different facade must not retarget the display's capture"
    assert_equal String, @layout.instance_variable_get(:@root_task_class)
  end

  # === Message queue ===

  def test_queue_message_stores_message
    @layout.on_start
    @layout.queue_message("Hello World")
    @layout.on_stop

    assert_includes @output.string, "Hello World"
  end

  def test_queue_message_multiple_messages
    @layout.on_start
    @layout.queue_message("Message 1")
    @layout.queue_message("Message 2")
    @layout.on_stop

    assert_includes @output.string, "Message 1"
    assert_includes @output.string, "Message 2"
  end

  # === Custom template ===

  def test_accepts_custom_theme
    custom_theme = Taski::Progress::Theme::Base.new
    layout = Taski::Progress::Layout::Base.new(output: @output, theme: custom_theme)
    assert_kind_of Taski::Progress::Layout::Base, layout
  end

  # === Thread safety ===

  def test_concurrent_on_task_updated_is_safe
    task_classes = 10.times.map { Class.new }
    threads = task_classes.map do |tc|
      Thread.new do
        @layout.on_task_updated(tc, previous_state: nil, current_state: :pending, phase: :run, timestamp: Time.now)
      end
    end
    threads.each(&:join)

    task_classes.each do |tc|
      assert @layout.task_registered?(tc)
    end
  end

  def test_concurrent_on_task_updated_state_change_is_safe
    task_class = Class.new
    @layout.on_task_updated(task_class, previous_state: nil, current_state: :pending, phase: :run, timestamp: Time.now)

    threads = 10.times.map do
      Thread.new do
        @layout.on_task_updated(task_class, previous_state: :pending, current_state: :running, phase: :run, timestamp: Time.now)
      end
    end
    threads.each(&:join)
    # No error raised
  end

  private

  # A minimal facade stub whose output_capture can be swapped to simulate a
  # phase rebuilding its router.
  def stub_facade(root:, capture:)
    facade = Object.new
    facade.define_singleton_method(:root_task_class) { root }
    facade.define_singleton_method(:output_capture) { capture }
    facade
  end

  def current_output_capture
    @layout.instance_variable_get(:@output_capture)
  end
end

class TestLayoutBaseThemeRendering < Minitest::Test
  def setup
    @output = StringIO.new
    @layout = Taski::Progress::Layout::Base.new(output: @output)
  end

  def teardown
    @layout.stop_spinner_timer
  end

  def test_render_theme_dispatches_to_theme_method
    custom_theme = Class.new(Taski::Progress::Theme::Base) do
      def task_start(task:, execution: nil)
        "#{green("GO")} #{short_name(task.name)}"
      end
    end.new
    layout = Taski::Progress::Layout::Base.new(output: @output, theme: custom_theme)

    result = layout.send(:render_theme, :task_start,
      task: Taski::Progress::TaskInfo.new(name: "MyModule::MyTask"))

    assert_equal "\e[32mGO\e[0m MyTask", result
  end

  def test_render_theme_coerces_result_to_string
    custom_theme = Class.new(Taski::Progress::Theme::Base) do
      def task_start(task:, execution: nil)
        42
      end
    end.new
    layout = Taski::Progress::Layout::Base.new(output: @output, theme: custom_theme)

    result = layout.send(:render_theme, :task_start, task: Taski::Progress::TaskInfo.new)

    assert_equal "42", result
  end

  def test_render_theme_passes_both_keywords
    spy_theme = Class.new(Taski::Progress::Theme::Base) do
      def task_start(task:, execution: nil)
        "task=#{task.name} execution=#{execution.done_count}/#{execution.total_count}"
      end
    end.new
    layout = Taski::Progress::Layout::Base.new(output: @output, theme: spy_theme)

    result = layout.send(:render_theme, :task_start,
      task: Taski::Progress::TaskInfo.new(name: "T"),
      execution: Taski::Progress::ExecutionInfo.new(done_count: 1, total_count: 3))

    assert_equal "task=T execution=1/3", result
  end

  def test_execution_info_carries_current_spinner_index
    @layout.instance_variable_set(:@spinner_index, 7)
    info = @layout.send(:execution_info)

    assert_equal 7, info.spinner_index
  end

  def test_execution_info_accepts_overrides
    info = @layout.send(:execution_info, state: :completed, task_names: ["A"])

    assert_equal :completed, info.state
    assert_equal ["A"], info.task_names
    assert_equal 0, info.done_count
  end

  def test_spinner_index_increments
    @layout.start_spinner_timer
    initial_index = @layout.spinner_index

    # Poll for spinner index change with timeout (more robust than fixed sleep)
    timeout = 1.0  # 1 second timeout
    start_time = Time.now
    new_index = initial_index
    while new_index == initial_index && (Time.now - start_time) < timeout
      sleep 0.02
      new_index = @layout.spinner_index
    end

    @layout.stop_spinner_timer

    assert new_index != initial_index, "Spinner index should have changed within timeout"
  end

  def test_stop_spinner_timer_stops_incrementing
    @layout.start_spinner_timer
    @layout.stop_spinner_timer
    index_after_stop = @layout.spinner_index
    sleep 0.15
    index_later = @layout.spinner_index

    assert_equal index_after_stop, index_later
  end

  def test_spinner_timer_does_not_start_twice
    @layout.start_spinner_timer
    first_thread = @layout.instance_variable_get(:@spinner_timer)
    @layout.start_spinner_timer
    second_thread = @layout.instance_variable_get(:@spinner_timer)
    @layout.stop_spinner_timer

    assert_equal first_thread, second_thread
  end
end

class TestLayoutBaseRenderLoop < Minitest::Test
  def setup
    @output = StringIO.new
    @layout = Taski::Progress::Layout::Base.new(output: @output)
    @render_count = 0
  end

  def teardown
    @layout.send(:stop_render_loop)
  end

  def test_render_loop_calls_block_periodically
    count = 0
    @layout.send(:render_loop) { count += 1 }
    sleep 0.2
    @layout.send(:stop_render_loop)
    assert count > 0, "render_loop should have called the block at least once"
  end

  def test_stop_render_loop_stops_the_thread
    @layout.send(:render_loop) {}
    @layout.send(:stop_render_loop)
    thread = @layout.instance_variable_get(:@render_thread)
    assert_nil thread, "render_thread should be nil after stop_render_loop"
  end

  def test_stop_render_loop_stops_spinner_timer
    @layout.send(:render_loop) {}
    @layout.send(:stop_render_loop)
    assert_equal false, @layout.instance_variable_get(:@spinner_running)
  end

  def test_render_loop_starts_spinner_timer
    @layout.send(:render_loop) {}
    assert @layout.instance_variable_get(:@spinner_running), "spinner should be running during render_loop"
    @layout.send(:stop_render_loop)
  end

  def test_stop_render_loop_without_start_is_safe
    @layout.send(:stop_render_loop)
    # No error raised
  end
end

class TestLayoutBaseStateTransitions < Minitest::Test
  def setup
    @output = StringIO.new
    @layout = Taski::Progress::Layout::Base.new(output: @output)
    @task_class = Class.new
    @now = Time.now
    @layout.on_task_updated(@task_class, previous_state: nil, current_state: :pending, phase: :run, timestamp: @now)
  end

  def test_pending_to_running_allowed
    @layout.on_task_updated(@task_class, previous_state: :pending, current_state: :running, phase: :run, timestamp: @now)
    assert_equal :running, @layout.task_state(@task_class)
  end

  def test_running_to_completed_allowed
    @layout.on_task_updated(@task_class, previous_state: :pending, current_state: :running, phase: :run, timestamp: @now)
    @layout.on_task_updated(@task_class, previous_state: :running, current_state: :completed, phase: :run, timestamp: @now + 0.1)
    assert_equal :completed, @layout.task_state(@task_class)
  end

  def test_completed_to_running_blocked
    @layout.on_task_updated(@task_class, previous_state: :pending, current_state: :running, phase: :run, timestamp: @now)
    @layout.on_task_updated(@task_class, previous_state: :running, current_state: :completed, phase: :run, timestamp: @now + 0.1)
    @layout.on_task_updated(@task_class, previous_state: :completed, current_state: :running, phase: :run, timestamp: @now + 0.2)
    # Should remain completed (nested executor re-execution guard)
    assert_equal :completed, @layout.task_state(@task_class)
  end

  def test_failed_to_running_blocked
    @layout.on_task_updated(@task_class, previous_state: :pending, current_state: :running, phase: :run, timestamp: @now)
    @layout.on_task_updated(@task_class, previous_state: :running, current_state: :failed, phase: :run, timestamp: @now + 0.1)
    @layout.on_task_updated(@task_class, previous_state: :failed, current_state: :running, phase: :run, timestamp: @now + 0.2)
    # Should remain failed
    assert_equal :failed, @layout.task_state(@task_class)
  end

  def test_skipped_state_transition
    @layout.on_task_updated(@task_class, previous_state: :pending, current_state: :skipped, phase: :run, timestamp: @now)
    assert_equal :skipped, @layout.task_state(@task_class)
  end

  def test_skipped_to_running_blocked
    @layout.on_task_updated(@task_class, previous_state: :pending, current_state: :skipped, phase: :run, timestamp: @now)
    @layout.on_task_updated(@task_class, previous_state: :skipped, current_state: :running, phase: :run, timestamp: @now + 0.1)
    # Should remain skipped (finalized state)
    assert_equal :skipped, @layout.task_state(@task_class)
  end

  def test_skipped_included_in_done_count
    task2 = Class.new
    now = Time.now

    output = StringIO.new
    layout = Taski::Progress::Layout::Base.new(output: output)
    layout.on_task_updated(@task_class, previous_state: nil, current_state: :pending, phase: :run, timestamp: now)
    layout.on_task_updated(task2, previous_state: nil, current_state: :pending, phase: :run, timestamp: now)
    layout.on_task_updated(@task_class, previous_state: :pending, current_state: :running, phase: :run, timestamp: now)
    layout.on_task_updated(@task_class, previous_state: :running, current_state: :completed, phase: :run, timestamp: now + 0.1)
    layout.on_task_updated(task2, previous_state: :pending, current_state: :skipped, phase: :run, timestamp: now)

    ctx = layout.send(:execution_context)
    assert_equal 2, ctx[:done_count], "done_count should include skipped tasks"
    assert_equal 1, ctx[:skipped_count], "skipped_count should be 1"
    assert_equal 1, ctx[:completed_count], "completed_count should not include skipped"
  end
end

# Pins which TaskInfo/ExecutionInfo fields the layout delivers to theme methods
# for each event — every theme method receives BOTH task: and execution:
# (either may be nil-fielded), so custom themes can mix task and execution data
# freely. Spy themes (plain Ruby) replace the old Liquid template spies;
# assertions are unchanged from the Liquid era.
class TestLayoutBaseCommonVariables < Minitest::Test
  def setup
    @output = StringIO.new
    @layout = Taski::Progress::Layout::Base.new(output: @output)
  end

  def test_task_start_can_use_duration_field
    custom_theme = Class.new(Taski::Progress::Theme::Base) do
      def task_start(task:, execution: nil)
        "#{task.name}#{" took #{task.duration}ms" if task.duration}"
      end
    end.new

    layout = Taski::Progress::Layout::Base.new(output: @output, theme: custom_theme)
    result = layout.send(:render_task_started, stub_task_class("MyTask"))

    # duration is nil for task_start, so the conditional must not render
    assert_equal "MyTask", result
  end

  def test_task_success_can_use_error_message_field
    custom_theme = Class.new(Taski::Progress::Theme::Base) do
      def task_success(task:, execution: nil)
        "#{task.name} done#{" (had error)" if task.error_message}"
      end
    end.new

    layout = Taski::Progress::Layout::Base.new(output: @output, theme: custom_theme)
    result = layout.send(:render_task_succeeded, stub_task_class("MyTask"), task_duration: 100)

    # error_message is nil for success, so the conditional must not render
    assert_equal "MyTask done", result
  end

  def test_execution_complete_receives_nil_task
    custom_theme = Class.new(Taski::Progress::Theme::Base) do
      def execution_complete(execution:, task: nil)
        "Done: #{execution.done_count}/#{execution.total_count}#{" (#{task.name})" if task&.name}"
      end
    end.new

    layout = Taski::Progress::Layout::Base.new(output: @output, theme: custom_theme)
    result = layout.send(:render_execution_completed, done_count: 5, total_count: 5, total_duration: 1000)

    # task is nil for execution_complete, so the conditional must not render
    assert_equal "Done: 5/5", result
  end

  def test_task_and_execution_info_available_in_any_template
    custom_theme = Class.new(Taski::Progress::Theme::Base) do
      def task_start(task:, execution: nil)
        [
          "task.name:#{task.name}",
          "task.state:#{task.state}",
          "task.duration:#{task.duration}",
          "task.error_message:#{task.error_message}",
          "execution.state:#{execution.state}",
          "execution.pending_count:#{execution.pending_count}",
          "execution.done_count:#{execution.done_count}",
          "execution.completed_count:#{execution.completed_count}",
          "execution.failed_count:#{execution.failed_count}",
          "execution.total_count:#{execution.total_count}",
          "execution.root_task_name:#{execution.root_task_name}"
        ].join("|")
      end
    end.new

    layout = Taski::Progress::Layout::Base.new(output: @output, theme: custom_theme)
    result = layout.send(:render_task_started, stub_task_class("MyTask"))

    assert_includes result, "task.name:MyTask"
    assert_includes result, "task.state:running"
    # nil fields interpolate to empty without raising
    assert_includes result, "task.duration:|"
    assert_includes result, "task.error_message:|"
    assert_includes result, "execution.state:running"
  end

  def test_task_info_is_available_in_template
    custom_theme = Class.new(Taski::Progress::Theme::Base) do
      def task_start(task:, execution: nil)
        "#{task.name} (#{task.state})"
      end
    end.new

    layout = Taski::Progress::Layout::Base.new(output: @output, theme: custom_theme)
    result = layout.send(:render_task_started, stub_task_class("MyTask"))

    assert_equal "MyTask (running)", result
  end

  def test_execution_info_is_available_in_template
    custom_theme = Class.new(Taski::Progress::Theme::Base) do
      def execution_complete(execution:, task: nil)
        "[#{execution.done_count}/#{execution.total_count}] (#{execution.total_duration}ms)"
      end
    end.new

    layout = Taski::Progress::Layout::Base.new(output: @output, theme: custom_theme)
    result = layout.send(:render_execution_completed, done_count: 5, total_count: 10, total_duration: 1500)

    assert_equal "[5/10] (1500ms)", result
  end

  def test_task_info_has_all_task_specific_fields
    custom_theme = Class.new(Taski::Progress::Theme::Base) do
      def task_fail(task:, execution: nil)
        "#{task.name}|#{task.state}|#{task.error_message}"
      end
    end.new

    layout = Taski::Progress::Layout::Base.new(output: @output, theme: custom_theme)
    result = layout.send(:render_task_failed, stub_task_class("FailTask"), error: StandardError.new("oops"))

    assert_equal "FailTask|failed|oops", result
  end

  def test_execution_info_has_all_execution_fields
    custom_theme = Class.new(Taski::Progress::Theme::Base) do
      def execution_fail(execution:, task: nil)
        "#{execution.failed_count}/#{execution.total_count} failed (#{execution.state})"
      end
    end.new

    layout = Taski::Progress::Layout::Base.new(output: @output, theme: custom_theme)
    result = layout.send(:render_execution_failed, failed_count: 2, total_count: 5, total_duration: 1000)

    assert_equal "2/5 failed (failed)", result
  end

  def test_render_task_skipped
    custom_theme = Class.new(Taski::Progress::Theme::Base) do
      def task_skip(task:, execution: nil)
        "[SKIP] #{task.name}"
      end
    end.new

    layout = Taski::Progress::Layout::Base.new(output: @output, theme: custom_theme)
    result = layout.send(:render_task_skipped, stub_task_class("SkippedTask"))

    assert_equal "[SKIP] SkippedTask", result
  end

  def test_render_execution_completed_with_skipped_count
    custom_theme = Class.new(Taski::Progress::Theme::Base) do
      def execution_complete(execution:, task: nil)
        "#{execution.done_count}/#{execution.total_count}#{" (#{execution.skipped_count} skipped)" if execution.skipped_count > 0}"
      end
    end.new

    layout = Taski::Progress::Layout::Base.new(output: @output, theme: custom_theme)
    result = layout.send(:render_execution_completed, done_count: 5, total_count: 5, total_duration: 1000, skipped_count: 2)

    assert_equal "5/5 (2 skipped)", result
  end

  def test_render_for_task_event_dispatches_skipped
    custom_theme = Class.new(Taski::Progress::Theme::Base) do
      def task_skip(task:, execution: nil)
        "[SKIP] #{task.name}"
      end
    end.new

    layout = Taski::Progress::Layout::Base.new(output: @output, theme: custom_theme)
    result = layout.send(:render_for_task_event, stub_task_class("MyTask"), :skipped, nil, nil)

    assert_equal "[SKIP] MyTask", result
  end

  def test_task_template_can_access_execution_context
    # Task-level theme methods also receive the live execution tallies
    custom_theme = Class.new(Taski::Progress::Theme::Base) do
      def task_fail(task:, execution: nil)
        "[#{execution.done_count}/#{execution.total_count}] #{task.name}: #{task.error_message}"
      end
    end.new

    layout = Taski::Progress::Layout::Base.new(output: @output, theme: custom_theme)

    # Set up tasks via on_task_updated
    task1 = stub_task_class("Task1")
    task2 = stub_task_class("Task2")
    task3 = stub_task_class("FailedTask")
    now = Time.now
    [task1, task2, task3].each do |tc|
      layout.on_task_updated(tc, previous_state: nil, current_state: :pending, phase: :run, timestamp: now)
    end
    [task1, task2].each do |tc|
      layout.on_task_updated(tc, previous_state: :pending, current_state: :running, phase: :run, timestamp: now)
      layout.on_task_updated(tc, previous_state: :running, current_state: :completed, phase: :run, timestamp: now + 0.1)
    end

    result = layout.send(:render_task_failed, task3, error: StandardError.new("connection refused"))

    # done_count = 2 (completed tasks), total_count = 3 (registered tasks)
    assert_equal "[2/3] FailedTask: connection refused", result
  end

  # Clean render methods should use unified state names (:running, :completed, :failed)
  # NOT the old separate names (:cleaning, :clean_completed, :clean_failed)

  def test_render_clean_started_uses_running_state
    task = stub_task_class("CleanTask")
    custom_theme = Class.new(Taski::Progress::Theme::Base) do
      def clean_start(task:, execution: nil) = "state=#{task.state}"
    end.new
    layout = Taski::Progress::Layout::Base.new(output: @output, theme: custom_theme)

    result = layout.send(:render_clean_started, task)
    assert_equal "state=running", result
  end

  def test_render_clean_succeeded_uses_completed_state
    task = stub_task_class("CleanTask")
    custom_theme = Class.new(Taski::Progress::Theme::Base) do
      def clean_success(task:, execution: nil) = "state=#{task.state}"
    end.new
    layout = Taski::Progress::Layout::Base.new(output: @output, theme: custom_theme)

    result = layout.send(:render_clean_succeeded, task, task_duration: nil)
    assert_equal "state=completed", result
  end

  def test_render_clean_failed_uses_failed_state
    task = stub_task_class("CleanTask")
    custom_theme = Class.new(Taski::Progress::Theme::Base) do
      def clean_fail(task:, execution: nil) = "state=#{task.state}"
    end.new
    layout = Taski::Progress::Layout::Base.new(output: @output, theme: custom_theme)

    result = layout.send(:render_clean_failed, task, error: nil)
    assert_equal "state=failed", result
  end

  private

  def stub_task_class(name)
    klass = Class.new
    klass.define_singleton_method(:name) { name }
    klass
  end
end
