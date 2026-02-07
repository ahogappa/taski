# frozen_string_literal: true

require_relative "test_helper"
require_relative "fixtures/error_tasks"

class TestUserAbort < Minitest::Test
  include TaskiTestHelper

  def setup
    setup_taski_test
    ErrorFixtures::ExecutionTracker.clear
  end

  # Test that TaskAbortException can be raised to abort a task
  def test_user_can_abort_task_with_exception
    error = assert_raises(Taski::TaskAbortException) do
      ErrorFixtures::AbortTask.value
    end

    assert_equal "User requested abort", error.message
  end

  # Test that TaskAbortException propagates to dependent tasks
  def test_abort_propagates_to_dependent_tasks
    assert_raises(Taski::TaskAbortException) do
      ErrorFixtures::AbortPropagationDependent.result
    end

    executed = ErrorFixtures::ExecutionTracker.executed
    assert_includes executed, :task_a
    assert_includes executed, :task_b
  end

  # Test abort message is preserved through the exception chain
  def test_abort_message_is_preserved
    error = assert_raises(Taski::TaskAbortException) do
      ErrorFixtures::AbortMessageTask.data
    end

    assert_includes error.message, "Custom abort message"
  end

  # Test graceful shutdown: In the new design, each Task execution has its own registry.
  # When a task raises TaskAbortException, it only affects its own execution context,
  # not other independent executions. This test verifies that behavior.
  # Intentionally inline: uses independent thread-based execution, not the pipeline.
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
  # Intentionally inline: tests progress spy mock behavior, task content is irrelevant.
  def test_progress_display_cleanup_on_exception
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
    Taski.progress_display = progress_spy

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
    Taski.reset_progress_display!
  end
end
