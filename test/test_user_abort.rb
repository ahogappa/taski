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

  # Test graceful shutdown: running tasks complete, pending tasks don't start
  def test_graceful_shutdown_completes_running_tasks_only
    execution_log = []
    completion_log = []

    # Task A - runs for a while, should complete
    task_a = Class.new(Taski::Task) do
      exports :value

      define_method(:run) do
        execution_log << :task_a_started
        sleep 0.2
        execution_log << :task_a_working
        @value = "completed"
        completion_log << :task_a_completed
      end
    end

    # Task B - fails quickly
    task_b = Class.new(Taski::Task) do
      exports :result

      define_method(:run) do
        execution_log << :task_b_started
        sleep 0.05
        raise Taski::TaskAbortException, "Task B aborted"
      end
    end

    # Task C - depends on A, should NOT start
    task_c = Class.new(Taski::Task) do
      exports :data

      define_method(:run) do
        execution_log << :task_c_started
        @data = task_a.value
        completion_log << :task_c_completed
      end
    end

    # Task D - independent, should NOT start
    task_d = Class.new(Taski::Task) do
      exports :output

      define_method(:run) do
        execution_log << :task_d_started
        @output = "done"
        completion_log << :task_d_completed
      end
    end

    # Start multiple tasks in parallel
    threads = [
      Thread.new do
        task_a.value
      rescue
        nil
      end,
      Thread.new do
        task_b.result
      rescue
        nil
      end,
      Thread.new do
        sleep 0.1
        task_c.data
      rescue
        nil
      end,
      Thread.new do
        sleep 0.1
        task_d.output
      rescue
        nil
      end
    ]

    threads.each(&:join)

    # Task A should have started and completed (was already running)
    assert_includes execution_log, :task_a_started
    assert_includes completion_log, :task_a_completed

    # Task B should have started (and failed)
    assert_includes execution_log, :task_b_started

    # Tasks C and D should NOT have started (pending when abort happened)
    refute_includes execution_log, :task_c_started
    refute_includes execution_log, :task_d_started
  end
end
