# frozen_string_literal: true

require "test_helper"
require "stringio"
require "taski/progress/theme/base"
require "taski/progress/theme/default"
require "taski/progress/theme/compact"
require "taski/progress/layout/base"
require "taski/progress/layout/theme_drop"

class TestLayoutBase < Minitest::Test
  def setup
    @output = StringIO.new
    @layout = Taski::Progress::Layout::Base.new(output: @output)
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
    @layout.on_start  # Nested call
    @layout.on_stop
    # First stop shouldn't finalize
    @layout.on_stop
    # Second stop finalizes
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

  def test_on_ready_only_sets_root_task_once
    @layout.context = mock_execution_facade(root_task_class: String)
    @layout.on_ready

    @layout.context = mock_execution_facade(root_task_class: Integer)
    @layout.on_ready

    @layout.on_start
    assert_includes @output.string, "String"
    refute_includes @output.string, "Integer"
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

  def mock_execution_facade(root_task_class:, output_capture: nil)
    graph = Taski::StaticAnalysis::DependencyGraph.new
    graph.build_from_cached(root_task_class) if root_task_class.respond_to?(:cached_dependencies)

    ctx = Object.new
    ctx.define_singleton_method(:root_task_class) { root_task_class }
    ctx.define_singleton_method(:output_capture) { output_capture }
    ctx.define_singleton_method(:dependency_graph) { graph }
    ctx
  end
end

class TestLayoutBaseLiquidRendering < Minitest::Test
  def setup
    @output = StringIO.new
    @layout = Taski::Progress::Layout::Base.new(output: @output)
  end

  def teardown
    @layout.stop_spinner_timer
  end

  def test_initialize_creates_liquid_environment
    assert @layout.instance_variable_get(:@liquid_environment)
  end

  def test_initialize_creates_theme_drop
    drop = @layout.instance_variable_get(:@theme_drop)
    assert_instance_of Taski::Progress::Layout::ThemeDrop, drop
  end

  def test_render_template_string_with_color_filter
    result = @layout.render_template_string(
      "{{ status | green }}",
      status: "OK"
    )

    assert_equal "\e[32mOK\e[0m", result
  end

  def test_render_template_string_with_spinner_tag
    result = @layout.render_template_string(
      "{% spinner %} Loading",
      spinner_index: 0
    )

    assert_equal "⠋ Loading", result
  end

  def test_render_template_string_passes_spinner_index
    result = @layout.render_template_string(
      "{% spinner %}",
      spinner_index: 3
    )

    assert_equal "⠸", result
  end

  def test_render_template_string_with_multiple_variables
    result = @layout.render_template_string(
      "{% spinner %} {{ task_name | green }} - {{ status | dim }}",
      task_name: "MyTask",
      status: "running",
      spinner_index: 0
    )

    assert_equal "⠋ \e[32mMyTask\e[0m - \e[2mrunning\e[0m", result
  end

  def test_render_template_string_uses_custom_theme_colors
    custom_theme = Class.new(Taski::Progress::Theme::Base) do
      def color_red
        "\e[91m"  # bright red
      end
    end.new

    layout = Taski::Progress::Layout::Base.new(output: @output, theme: custom_theme)
    result = layout.render_template_string("{{ text | red }}", text: "error")

    assert_equal "\e[91merror\e[0m", result
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

class TestLayoutBaseCommonVariables < Minitest::Test
  def setup
    @output = StringIO.new
    @layout = Taski::Progress::Layout::Base.new(output: @output)
  end

  # All templates should have access to the same common variables
  # even if the value is nil when not applicable

  def test_task_start_can_use_duration_variable
    # Create a custom template that uses duration in task_start
    custom_theme = Class.new(Taski::Progress::Theme::Base) do
      def task_start
        "{{ task.name }}{% if task.duration %} took {{ task.duration }}ms{% endif %}"
      end
    end.new

    layout = Taski::Progress::Layout::Base.new(output: @output, theme: custom_theme)
    result = layout.send(:render_task_started, stub_task_class("MyTask"))

    # duration is nil for task_start, so the if block should not render
    assert_equal "MyTask", result
  end

  def test_task_success_can_use_task_error_message_variable
    # Create a custom template that checks for task.error_message in task_success
    custom_theme = Class.new(Taski::Progress::Theme::Base) do
      def task_success
        "{{ task.name }} done{% if task.error_message %} (had error){% endif %}"
      end
    end.new

    layout = Taski::Progress::Layout::Base.new(output: @output, theme: custom_theme)
    result = layout.send(:render_task_succeeded, stub_task_class("MyTask"), task_duration: 100)

    # error_message is nil for success, so the if block should not render
    assert_equal "MyTask done", result
  end

  def test_execution_complete_can_use_task_name_variable
    # Create a custom template that uses task.name in execution_complete
    custom_theme = Class.new(Taski::Progress::Theme::Base) do
      def execution_complete
        "Done: {{ execution.completed_count }}/{{ execution.total_count }}{% if task.name %} ({{ task.name }}){% endif %}"
      end
    end.new

    layout = Taski::Progress::Layout::Base.new(output: @output, theme: custom_theme)
    result = layout.send(:render_execution_completed, completed_count: 5, total_count: 5, total_duration: 1000)

    # task.name is nil for execution_complete, so the if block should not render
    assert_equal "Done: 5/5", result
  end

  def test_task_and_execution_drops_available_in_any_template
    # Create a template that uses task and execution drops
    custom_theme = Class.new(Taski::Progress::Theme::Base) do
      def task_start
        [
          "task.name:{{ task.name }}",
          "task.state:{{ task.state }}",
          "task.duration:{{ task.duration }}",
          "task.error_message:{{ task.error_message }}",
          "execution.state:{{ execution.state }}",
          "execution.pending_count:{{ execution.pending_count }}",
          "execution.done_count:{{ execution.done_count }}",
          "execution.completed_count:{{ execution.completed_count }}",
          "execution.failed_count:{{ execution.failed_count }}",
          "execution.total_count:{{ execution.total_count }}",
          "execution.root_task_name:{{ execution.root_task_name }}"
        ].join("|")
      end
    end.new

    layout = Taski::Progress::Layout::Base.new(output: @output, theme: custom_theme)
    result = layout.send(:render_task_started, stub_task_class("MyTask"))

    # Task drop should have name and state
    assert_includes result, "task.name:MyTask"
    assert_includes result, "task.state:running"
    # Others should be empty but the variable names should still render (not cause errors)
    assert_includes result, "task.duration:"
    assert_includes result, "task.error_message:"
    assert_includes result, "execution.state:running"
  end

  def test_task_drop_is_available_in_template
    # Create a template that uses task drop
    custom_theme = Class.new(Taski::Progress::Theme::Base) do
      def task_start
        "{{ task.name }} ({{ task.state }})"
      end
    end.new

    layout = Taski::Progress::Layout::Base.new(output: @output, theme: custom_theme)
    result = layout.send(:render_task_started, stub_task_class("MyTask"))

    assert_equal "MyTask (running)", result
  end

  def test_execution_drop_is_available_in_template
    # Create a template that uses execution drop
    custom_theme = Class.new(Taski::Progress::Theme::Base) do
      def execution_complete
        "[{{ execution.completed_count }}/{{ execution.total_count }}] ({{ execution.total_duration }}ms)"
      end
    end.new

    layout = Taski::Progress::Layout::Base.new(output: @output, theme: custom_theme)
    result = layout.send(:render_execution_completed, completed_count: 5, total_count: 10, total_duration: 1500)

    assert_equal "[5/10] (1500ms)", result
  end

  def test_task_drop_has_all_task_specific_fields
    custom_theme = Class.new(Taski::Progress::Theme::Base) do
      def task_fail
        "{{ task.name }}|{{ task.state }}|{{ task.error_message }}"
      end
    end.new

    layout = Taski::Progress::Layout::Base.new(output: @output, theme: custom_theme)
    result = layout.send(:render_task_failed, stub_task_class("FailTask"), error: StandardError.new("oops"))

    assert_equal "FailTask|failed|oops", result
  end

  def test_execution_drop_has_all_execution_fields
    custom_theme = Class.new(Taski::Progress::Theme::Base) do
      def execution_fail
        "{{ execution.failed_count }}/{{ execution.total_count }} failed ({{ execution.state }})"
      end
    end.new

    layout = Taski::Progress::Layout::Base.new(output: @output, theme: custom_theme)
    result = layout.send(:render_execution_failed, failed_count: 2, total_count: 5, total_duration: 1000)

    assert_equal "2/5 failed (failed)", result
  end

  def test_render_task_skipped
    custom_theme = Class.new(Taski::Progress::Theme::Base) do
      def task_skip
        "[SKIP] {{ task.name }}"
      end
    end.new

    layout = Taski::Progress::Layout::Base.new(output: @output, theme: custom_theme)
    result = layout.send(:render_task_skipped, stub_task_class("SkippedTask"))

    assert_equal "[SKIP] SkippedTask", result
  end

  def test_render_execution_completed_with_skipped_count
    custom_theme = Class.new(Taski::Progress::Theme::Base) do
      def execution_complete
        "{{ execution.completed_count }}/{{ execution.total_count }}{% if execution.skipped_count > 0 %} ({{ execution.skipped_count }} skipped){% endif %}"
      end
    end.new

    layout = Taski::Progress::Layout::Base.new(output: @output, theme: custom_theme)
    result = layout.send(:render_execution_completed, completed_count: 3, total_count: 5, total_duration: 1000, skipped_count: 2)

    assert_equal "3/5 (2 skipped)", result
  end

  def test_render_for_task_event_dispatches_skipped
    custom_theme = Class.new(Taski::Progress::Theme::Base) do
      def task_skip
        "[SKIP] {{ task.name }}"
      end
    end.new

    layout = Taski::Progress::Layout::Base.new(output: @output, theme: custom_theme)
    result = layout.send(:render_for_task_event, stub_task_class("MyTask"), :skipped, nil, nil)

    assert_equal "[SKIP] MyTask", result
  end

  def test_task_template_can_access_execution_context
    # Task-level templates should also have access to execution context
    custom_theme = Class.new(Taski::Progress::Theme::Base) do
      def task_fail
        "[{{ execution.done_count }}/{{ execution.total_count }}] {{ task.name }}: {{ task.error_message }}"
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
      def clean_start = "state={{ task.state }}"
    end.new
    layout = Taski::Progress::Layout::Base.new(output: @output, theme: custom_theme)

    result = layout.send(:render_clean_started, task)
    assert_equal "state=running", result
  end

  def test_render_clean_succeeded_uses_completed_state
    task = stub_task_class("CleanTask")
    custom_theme = Class.new(Taski::Progress::Theme::Base) do
      def clean_success = "state={{ task.state }}"
    end.new
    layout = Taski::Progress::Layout::Base.new(output: @output, theme: custom_theme)

    result = layout.send(:render_clean_succeeded, task, task_duration: nil)
    assert_equal "state=completed", result
  end

  def test_render_clean_failed_uses_failed_state
    task = stub_task_class("CleanTask")
    custom_theme = Class.new(Taski::Progress::Theme::Base) do
      def clean_fail = "state={{ task.state }}"
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
