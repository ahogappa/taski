# frozen_string_literal: true

require "test_helper"

class TestSharedState < Minitest::Test
  def setup
    @shared_state = Taski::Execution::SharedState.new
  end

  def test_register_and_get_wrapper
    task_class = Class.new(Taski::Task) do
      exports :value
      def run
        @value = "test"
      end
    end

    registry = Taski::Execution::Registry.new
    task_instance = TaskiTestHelper.build_task_instance(task_class)
    wrapper = Taski::Execution::TaskWrapper.new(task_instance, registry: registry)

    @shared_state.register(task_class, wrapper)
    assert_equal wrapper, @shared_state.get_wrapper(task_class)
  end

  def test_state_transitions
    task_class = Class.new(Taski::Task) do
      exports :value
      def run
        @value = "test"
      end
    end

    registry = Taski::Execution::Registry.new
    task_instance = TaskiTestHelper.build_task_instance(task_class)
    wrapper = Taski::Execution::TaskWrapper.new(task_instance, registry: registry)

    @shared_state.register(task_class, wrapper)

    # Initially pending
    refute @shared_state.completed?(task_class)

    # Mark running - returns true first time
    assert @shared_state.mark_running(task_class)

    # Mark running again - returns false (already running)
    refute @shared_state.mark_running(task_class)

    refute @shared_state.completed?(task_class)

    # Mark completed
    @shared_state.mark_completed(task_class)
    assert @shared_state.completed?(task_class)
  end

  def test_request_dependency_returns_completed_for_finished_deps
    dep_class = Class.new(Taski::Task) do
      exports :value
      def run
        @value = "dep_value"
      end
    end

    registry = Taski::Execution::Registry.new
    task_instance = TaskiTestHelper.build_task_instance(dep_class)
    wrapper = Taski::Execution::TaskWrapper.new(task_instance, registry: registry)

    @shared_state.register(dep_class, wrapper)
    @shared_state.mark_running(dep_class)
    @shared_state.mark_completed(dep_class)

    thread_queue = Queue.new
    fiber = Fiber.new { Fiber.yield }

    result = @shared_state.request_dependency(dep_class, :value, thread_queue, fiber)
    assert_equal :completed, result[0]
    # The value should be accessible through the wrapper
    assert_equal wrapper, @shared_state.get_wrapper(dep_class)
  end

  def test_request_dependency_returns_wait_for_running_deps
    dep_class = Class.new(Taski::Task) do
      exports :value
      def run
        @value = "dep_value"
      end
    end

    registry = Taski::Execution::Registry.new
    task_instance = TaskiTestHelper.build_task_instance(dep_class)
    wrapper = Taski::Execution::TaskWrapper.new(task_instance, registry: registry)

    @shared_state.register(dep_class, wrapper)
    @shared_state.mark_running(dep_class)

    thread_queue = Queue.new
    fiber = Fiber.new { Fiber.yield }

    result = @shared_state.request_dependency(dep_class, :value, thread_queue, fiber)
    assert_equal :wait, result[0]
  end

  def test_request_dependency_returns_start_for_unknown_deps
    dep_class = Class.new(Taski::Task) do
      exports :value
      def run
        @value = "dep_value"
      end
    end

    thread_queue = Queue.new
    fiber = Fiber.new { Fiber.yield }

    result = @shared_state.request_dependency(dep_class, :value, thread_queue, fiber)
    assert_equal :start, result[0]
  end

  def test_waiter_notification_on_completion
    dep_class = Class.new(Taski::Task) do
      exports :value
      def run
        @value = "dep_value"
      end
    end

    registry = Taski::Execution::Registry.new
    task_instance = TaskiTestHelper.build_task_instance(dep_class)
    wrapper = Taski::Execution::TaskWrapper.new(task_instance, registry: registry)

    @shared_state.register(dep_class, wrapper)
    @shared_state.mark_running(dep_class)

    # Register a waiter
    thread_queue = Queue.new
    fiber = Fiber.new { Fiber.yield }

    @shared_state.request_dependency(dep_class, :value, thread_queue, fiber)

    # Simulate task completion - run the task first to set exported value
    task_instance.run
    wrapper.mark_completed(task_instance.value)
    @shared_state.mark_completed(dep_class)

    # Waiter should have been notified via thread_queue
    msg = thread_queue.pop
    assert_equal :resume, msg[0]
    assert_equal fiber, msg[1]
    # msg[2] is the resolved value
  end

  def test_mark_failed_propagates_error_to_waiters
    dep_class = Class.new(Taski::Task) do
      exports :value
      def run
        @value = "dep_value"
      end
    end

    registry = Taski::Execution::Registry.new
    task_instance = TaskiTestHelper.build_task_instance(dep_class)
    wrapper = Taski::Execution::TaskWrapper.new(task_instance, registry: registry)

    @shared_state.register(dep_class, wrapper)
    @shared_state.mark_running(dep_class)

    # Register a waiter
    thread_queue = Queue.new
    fiber = Fiber.new { Fiber.yield }

    @shared_state.request_dependency(dep_class, :value, thread_queue, fiber)

    # Mark as failed
    test_error = StandardError.new("task failed")
    @shared_state.mark_failed(dep_class, test_error)

    # Waiter should have been notified with error
    msg = thread_queue.pop
    assert_equal :resume_error, msg[0]
    assert_equal fiber, msg[1]
    assert_equal test_error, msg[2]
  end

  def test_concurrent_access
    dep_class = Class.new(Taski::Task) do
      exports :value
      def run
        @value = "dep_value"
      end
    end

    registry = Taski::Execution::Registry.new
    task_instance = TaskiTestHelper.build_task_instance(dep_class)
    wrapper = Taski::Execution::TaskWrapper.new(task_instance, registry: registry)

    @shared_state.register(dep_class, wrapper)
    @shared_state.mark_running(dep_class)

    # Multiple threads requesting same dependency concurrently
    queues = 3.times.map { Queue.new }
    fibers = 3.times.map { Fiber.new { Fiber.yield } }

    threads = 3.times.map { |i|
      Thread.new do
        @shared_state.request_dependency(dep_class, :value, queues[i], fibers[i])
      end
    }
    threads.each(&:join)

    # Complete the dependency
    task_instance.run
    wrapper.mark_completed(task_instance.value)
    @shared_state.mark_completed(dep_class)

    # All waiters should have been notified
    queues.each do |q|
      msg = q.pop
      assert_equal :resume, msg[0]
    end
  end

  def test_request_dependency_for_pending_registered_task
    dep_class = Class.new(Taski::Task) do
      exports :value
      def run
        @value = "dep_value"
      end
    end

    registry = Taski::Execution::Registry.new
    task_instance = TaskiTestHelper.build_task_instance(dep_class)
    wrapper = Taski::Execution::TaskWrapper.new(task_instance, registry: registry)

    # Register but don't mark running
    @shared_state.register(dep_class, wrapper)

    thread_queue = Queue.new
    fiber = Fiber.new { Fiber.yield }

    # Pending task should return :start (needs to be started)
    result = @shared_state.request_dependency(dep_class, :value, thread_queue, fiber)
    assert_equal :start, result[0]
  end

  def test_second_request_dependency_returns_wait_not_start
    # After the first request_dependency returns :start, subsequent calls
    # for the same dep should return :wait (not another :start).
    dep_class = Class.new(Taski::Task) do
      exports :value
      def run
        @value = "dep_value"
      end
    end

    queue_a = Queue.new
    queue_b = Queue.new
    fiber_a = Fiber.new { Fiber.yield }
    fiber_b = Fiber.new { Fiber.yield }

    result_a = @shared_state.request_dependency(dep_class, :value, queue_a, fiber_a)
    assert_equal :start, result_a[0]

    # Second call should see :wait, not :start
    result_b = @shared_state.request_dependency(dep_class, :value, queue_b, fiber_b)
    assert_equal :wait, result_b[0],
      "Second request_dependency should return :wait, got #{result_b[0].inspect}"
  end
end
