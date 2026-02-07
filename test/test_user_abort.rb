# frozen_string_literal: true

require_relative "test_helper"

class TestUserAbort < Minitest::Test
  include TaskiTestHelper

  def setup
    setup_taski_test
  end

  # Test that TaskAbortException can be raised to abort a task
  def test_user_can_abort_task_with_exception
    # Define a task that can be aborted by the user
    task_class = Class.new(Taski::Task) do
      exports :result

      def run
        # Simulate work
        sleep 0.1

        # User decides to abort at this point
        raise Taski::TaskAbortException, "User requested abort"
      end
    end

    # The exception should propagate and abort the task
    error = assert_raises(Taski::TaskAbortException) do
      task_class.result
    end

    assert_equal "User requested abort", error.message
  end

  # Test that TaskAbortException propagates to dependent tasks
  def test_abort_propagates_to_dependent_tasks
    executed_tasks = []

    # Task A that will be aborted
    task_a = Class.new(Taski::Task) do
      exports :value

      define_method(:run) do
        executed_tasks << :task_a
        raise Taski::TaskAbortException, "Task A aborted"
      end
    end

    # Task B depends on A
    task_b = Class.new(Taski::Task) do
      exports :result

      define_method(:run) do
        executed_tasks << :task_b
        # This will raise TaskAbortException from Task A
        @result = task_a.value
      end
    end

    # Task B should raise TaskAbortException when accessing A's value
    assert_raises(Taski::TaskAbortException) do
      task_b.result
    end

    # Both tasks should have started execution
    # (Task B runs but fails when accessing A's value)
    assert_equal [:task_b, :task_a].sort, executed_tasks.sort
  end

  # Test abort message is preserved through the exception chain
  def test_abort_message_is_preserved
    task_class = Class.new(Taski::Task) do
      exports :data

      def run
        raise Taski::TaskAbortException, "Custom abort message"
      end
    end

    error = assert_raises(Taski::TaskAbortException) do
      task_class.data
    end

    assert_includes error.message, "Custom abort message"
  end

  # Test graceful shutdown: In the new design, each Task execution has its own registry.
  # When a task raises TaskAbortException, it only affects its own execution context,
  # not other independent executions. This test verifies that behavior.
  def test_graceful_shutdown_completes_running_tasks_only
    execution_log = []
    completion_log = []
    mutex = Mutex.new

    # Task A - runs for a while, should complete
    task_a = Class.new(Taski::Task) do
      exports :value

      define_method(:run) do
        mutex.synchronize { execution_log << :task_a_started }
        sleep 0.1
        mutex.synchronize { execution_log << :task_a_working }
        @value = "completed"
        mutex.synchronize { completion_log << :task_a_completed }
      end
    end

    # Task B - fails quickly with abort
    task_b = Class.new(Taski::Task) do
      exports :result

      define_method(:run) do
        mutex.synchronize { execution_log << :task_b_started }
        sleep 0.02
        raise Taski::TaskAbortException, "Task B aborted"
      end
    end

    # Task C - independent task
    task_c = Class.new(Taski::Task) do
      exports :data

      define_method(:run) do
        mutex.synchronize { execution_log << :task_c_started }
        @data = "c_data"
        mutex.synchronize { completion_log << :task_c_completed }
      end
    end

    # Start multiple independent tasks in parallel
    threads = [
      Thread.new do
        task_a.run
      rescue
        nil
      end,
      Thread.new do
        task_b.run
      rescue
        nil
      end,
      Thread.new do
        sleep 0.05
        task_c.run
      rescue
        nil
      end
    ]

    threads.each(&:join)

    # Task A should have started and completed (independent execution)
    assert_includes execution_log, :task_a_started
    assert_includes completion_log, :task_a_completed

    # Task B should have started (and failed)
    assert_includes execution_log, :task_b_started

    # Task C should also complete because each task has its own registry
    # (abort in task_b doesn't affect task_c's independent execution)
    assert_includes execution_log, :task_c_started
    assert_includes completion_log, :task_c_completed
  end

  # Test that progress display is cleaned up even when task raises an exception
  def test_progress_display_cleanup_on_exception
    # Temporarily enable progress display for this test
    original_env = ENV["TASKI_PROGRESS_DISABLE"]
    ENV.delete("TASKI_PROGRESS_DISABLE")

    stop_called = false

    # Create a spy progress display
    progress_spy = Object.new
    progress_spy.define_singleton_method(:set_root_task) { |_| }
    progress_spy.define_singleton_method(:set_output_capture) { |_| }
    progress_spy.define_singleton_method(:register_task) { |_| }
    progress_spy.define_singleton_method(:task_registered?) { |_| false }
    progress_spy.define_singleton_method(:update_task) { |_, **_| }
    progress_spy.define_singleton_method(:start) {}
    progress_spy.define_singleton_method(:stop) { stop_called = true }

    # Set the spy as the progress display
    Taski.instance_variable_set(:@progress_display, progress_spy)

    # Task that raises an exception
    task_class = Class.new(Taski::Task) do
      exports :result

      def run
        raise "Task failed"
      end
    end

    # Run the task (it should raise but still clean up)
    assert_raises(Taski::AggregateError) do
      task_class.result
    end

    # Verify stop was called despite the exception
    assert stop_called, "Progress display stop should be called even on exception"
  ensure
    ENV["TASKI_PROGRESS_DISABLE"] = original_env if original_env
    Taski.reset_progress_display!
  end
end
