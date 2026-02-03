# frozen_string_literal: true

require "test_helper"
require "stringio"
require "taski/execution/template/base"
require "taski/execution/template/default"
require "taski/execution/layout/base"

class TestLayoutBase < Minitest::Test
  def setup
    @output = StringIO.new
    @layout = Taski::Execution::Layout::Base.new(output: @output)
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
    # Clean state should be tracked
    assert_equal :cleaning, @layout.task_state(task_class)
  end

  def test_update_task_clean_completed_state
    task_class = Class.new
    @layout.register_task(task_class)
    @layout.update_task(task_class, state: :completed, duration: 100)
    @layout.update_task(task_class, state: :cleaning)
    @layout.update_task(task_class, state: :clean_completed, duration: 50)
    assert_equal :clean_completed, @layout.task_state(task_class)
  end

  # === Nest level management ===

  def test_start_and_stop_manage_nest_level
    @layout.start
    @layout.start  # Nested call
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

  def test_accepts_custom_template
    custom_template = Taski::Execution::Template::Base.new
    layout = Taski::Execution::Layout::Base.new(output: @output, template: custom_template)
    assert_kind_of Taski::Execution::Layout::Base, layout
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

class TestLayoutBaseTaskStateTransitions < Minitest::Test
  def setup
    @output = StringIO.new
    @layout = Taski::Execution::Layout::Base.new(output: @output)
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
