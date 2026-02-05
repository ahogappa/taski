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

  # === Observer interface tests ===

  def test_responds_to_observer_interface
    assert_respond_to @layout, :set_root_task
    assert_respond_to @layout, :register_task
    assert_respond_to @layout, :update_task
    assert_respond_to @layout, :register_section_impl
    assert_respond_to @layout, :update_group
    assert_respond_to @layout, :set_output_capture
    assert_respond_to @layout, :start
    assert_respond_to @layout, :stop
    assert_respond_to @layout, :queue_message
  end

  # === Task registration ===

  def test_register_task_tracks_new_task
    task_class = Class.new
    @layout.register_task(task_class)
    assert @layout.task_registered?(task_class)
  end

  def test_register_task_is_idempotent
    task_class = Class.new
    @layout.register_task(task_class)
    @layout.register_task(task_class)
    # No error raised
  end

  # === Task state management ===

  def test_update_task_running_changes_state
    task_class = Class.new
    @layout.register_task(task_class)
    @layout.update_task(task_class, state: :running)
    assert_equal :running, @layout.task_state(task_class)
  end

  def test_update_task_completed_changes_state
    task_class = Class.new
    @layout.register_task(task_class)
    @layout.update_task(task_class, state: :running)
    @layout.update_task(task_class, state: :completed, duration: 123.4)
    assert_equal :completed, @layout.task_state(task_class)
  end

  def test_update_task_failed_changes_state
    task_class = Class.new
    @layout.register_task(task_class)
    @layout.update_task(task_class, state: :running)
    error = StandardError.new("test error")
    @layout.update_task(task_class, state: :failed, error: error)
    assert_equal :failed, @layout.task_state(task_class)
  end

  def test_update_task_registers_if_not_registered
    task_class = Class.new
    @layout.update_task(task_class, state: :running)
    assert @layout.task_registered?(task_class)
  end

  # === Clean state management ===

  def test_update_task_cleaning_state
    task_class = Class.new
    @layout.register_task(task_class)
    @layout.update_task(task_class, state: :completed, duration: 100)
    @layout.update_task(task_class, state: :cleaning)
    # Clean state should be tracked (Phase 1: unified to :running)
    assert_equal :running, @layout.task_state(task_class)
  end

  def test_update_task_clean_completed_state
    task_class = Class.new
    @layout.register_task(task_class)
    @layout.update_task(task_class, state: :completed, duration: 100)
    @layout.update_task(task_class, state: :cleaning)
    @layout.update_task(task_class, state: :clean_completed, duration: 50)
    # Phase 1: unified to :completed
    assert_equal :completed, @layout.task_state(task_class)
  end

  # === Nest level management ===

  def test_start_and_stop_manage_nest_level
    @layout.start
    @layout.start # Nested call
    @layout.stop
    # First stop shouldn't finalize
    @layout.stop
    # Second stop finalizes
  end

  def test_stop_without_start_does_not_crash
    @layout.stop
    # No error raised
  end

  # === Root task ===

  def test_set_root_task_only_sets_once
    task1 = Class.new
    task2 = Class.new
    @layout.set_root_task(task1)
    @layout.set_root_task(task2)
    # First set wins - implementation detail checked via on_root_task_set
  end

  # === Section impl registration ===

  def test_register_section_impl_registers_impl_task
    section_class = Class.new
    impl_class = Class.new
    @layout.register_task(section_class)
    @layout.register_section_impl(section_class, impl_class)
    assert @layout.task_registered?(impl_class)
  end

  # === Message queue ===

  def test_queue_message_stores_message
    @layout.start
    @layout.queue_message("Hello World")
    @layout.stop

    assert_includes @output.string, "Hello World"
  end

  def test_queue_message_multiple_messages
    @layout.start
    @layout.queue_message("Message 1")
    @layout.queue_message("Message 2")
    @layout.stop

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

  def test_concurrent_register_task_is_safe
    task_classes = 10.times.map { Class.new }
    threads = task_classes.map do |tc|
      Thread.new { @layout.register_task(tc) }
    end
    threads.each(&:join)

    task_classes.each do |tc|
      assert @layout.task_registered?(tc)
    end
  end

  def test_concurrent_update_task_is_safe
    task_class = Class.new
    @layout.register_task(task_class)

    threads = 10.times.map do
      Thread.new { @layout.update_task(task_class, state: :running) }
    end
    threads.each(&:join)
    # No error raised
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
        "\e[91m" # bright red
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
    timeout = 1.0 # 1 second timeout
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

class TestLayoutBaseTaskStateTransitions < Minitest::Test
  def setup
    @output = StringIO.new
    @layout = Taski::Progress::Layout::Base.new(output: @output)
    @task_class = Class.new
    @layout.register_task(@task_class)
  end

  def test_pending_to_running_allowed
    @layout.update_task(@task_class, state: :running)
    assert_equal :running, @layout.task_state(@task_class)
  end

  def test_running_to_completed_allowed
    @layout.update_task(@task_class, state: :running)
    @layout.update_task(@task_class, state: :completed, duration: 100)
    assert_equal :completed, @layout.task_state(@task_class)
  end

  def test_completed_to_running_blocked
    @layout.update_task(@task_class, state: :running)
    @layout.update_task(@task_class, state: :completed, duration: 100)
    @layout.update_task(@task_class, state: :running)
    # Should remain completed (nested executor re-execution guard)
    assert_equal :completed, @layout.task_state(@task_class)
  end

  def test_failed_to_running_blocked
    @layout.update_task(@task_class, state: :running)
    @layout.update_task(@task_class, state: :failed, error: StandardError.new)
    @layout.update_task(@task_class, state: :running)
    # Should remain failed
    assert_equal :failed, @layout.task_state(@task_class)
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

  def test_task_template_can_access_execution_context
    # Task-level templates should also have access to execution context
    custom_theme = Class.new(Taski::Progress::Theme::Base) do
      def task_fail
        "[{{ execution.done_count }}/{{ execution.total_count }}] {{ task.name }}: {{ task.error_message }}"
      end
    end.new

    layout = Taski::Progress::Layout::Base.new(output: @output, theme: custom_theme)

    # Register some tasks to have counts
    task1 = stub_task_class("Task1")
    task2 = stub_task_class("Task2")
    task3 = stub_task_class("FailedTask")
    layout.register_task(task1)
    layout.register_task(task2)
    layout.register_task(task3)
    layout.update_task(task1, state: :completed, duration: 100)
    layout.update_task(task2, state: :completed, duration: 100)

    result = layout.send(:render_task_failed, task3, error: StandardError.new("connection refused"))

    # done_count = 2 (completed tasks), total_count = 3 (registered tasks)
    assert_equal "[2/3] FailedTask: connection refused", result
  end

  private

  def stub_task_class(name)
    klass = Class.new
    klass.define_singleton_method(:name) { name }
    klass
  end
end
