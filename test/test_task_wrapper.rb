# frozen_string_literal: true

require "test_helper"

class TestTaskWrapper < Minitest::Test
  def setup
    Taski::Task.reset! if defined?(Taski::Task)
    @registry = Taski::Execution::Registry.new
  end

  # ========================================
  # request_value tests
  # ========================================

  def test_request_value_on_completed_wrapper_returns_value
    task_class = Class.new(Taski::Task) do
      exports :value
      def run
        @value = "completed_value"
      end
    end

    wrapper = create_wrapper(task_class)
    wrapper.mark_running
    wrapper.task.run
    wrapper.mark_completed(wrapper.task.value)

    thread_queue = Queue.new
    fiber = Fiber.new { Fiber.yield }

    result = wrapper.request_value(:value, thread_queue, fiber)
    assert_instance_of Taski::Execution::FiberProtocol::DepCompleted, result
    assert_equal "completed_value", result.value
  end

  def test_request_value_on_failed_wrapper_returns_error
    task_class = Class.new(Taski::Task) do
      exports :value
      def run
        @value = "test"
      end
    end

    wrapper = create_wrapper(task_class)
    wrapper.mark_running
    error = StandardError.new("task failed")
    wrapper.mark_failed(error)

    thread_queue = Queue.new
    fiber = Fiber.new { Fiber.yield }

    result = wrapper.request_value(:value, thread_queue, fiber)
    assert_instance_of Taski::Execution::FiberProtocol::DepFailed, result
    assert_equal error, result.error
  end

  def test_request_value_on_running_wrapper_returns_wait
    task_class = Class.new(Taski::Task) do
      exports :value
      def run
        @value = "test"
      end
    end

    wrapper = create_wrapper(task_class)
    wrapper.mark_running

    thread_queue = Queue.new
    fiber = Fiber.new { Fiber.yield }

    result = wrapper.request_value(:value, thread_queue, fiber)
    assert_instance_of Taski::Execution::FiberProtocol::DepWaiting, result
  end

  def test_request_value_on_pending_wrapper_returns_start_and_transitions_to_running
    task_class = Class.new(Taski::Task) do
      exports :value
      def run
        @value = "test"
      end
    end

    wrapper = create_wrapper(task_class)

    thread_queue = Queue.new
    fiber = Fiber.new { Fiber.yield }

    result = wrapper.request_value(:value, thread_queue, fiber)
    assert_instance_of Taski::Execution::FiberProtocol::DepStarting, result
    assert_equal Taski::Execution::TaskWrapper::STATE_RUNNING, wrapper.state
  end

  def test_two_concurrent_request_value_on_pending_first_gets_start_second_gets_wait
    task_class = Class.new(Taski::Task) do
      exports :value
      def run
        @value = "test"
      end
    end

    wrapper = create_wrapper(task_class)

    queue_a = Queue.new
    queue_b = Queue.new
    fiber_a = Fiber.new { Fiber.yield }
    fiber_b = Fiber.new { Fiber.yield }

    result_a = wrapper.request_value(:value, queue_a, fiber_a)
    assert_instance_of Taski::Execution::FiberProtocol::DepStarting, result_a

    result_b = wrapper.request_value(:value, queue_b, fiber_b)
    assert_instance_of Taski::Execution::FiberProtocol::DepWaiting, result_b
  end

  def test_mark_completed_notifies_fiber_waiters
    task_class = Class.new(Taski::Task) do
      exports :value
      def run
        @value = "notified_value"
      end
    end

    wrapper = create_wrapper(task_class)
    wrapper.mark_running

    thread_queue = Queue.new
    fiber = Fiber.new { Fiber.yield }

    wrapper.request_value(:value, thread_queue, fiber)

    # Complete the task
    wrapper.task.run
    wrapper.mark_completed(wrapper.task.value)

    msg = thread_queue.pop
    assert_instance_of Taski::Execution::FiberProtocol::Resume, msg
    assert_equal fiber, msg.fiber
    assert_equal "notified_value", msg.value
  end

  def test_mark_failed_notifies_fiber_waiters_with_error
    task_class = Class.new(Taski::Task) do
      exports :value
      def run
        @value = "test"
      end
    end

    wrapper = create_wrapper(task_class)
    wrapper.mark_running

    thread_queue = Queue.new
    fiber = Fiber.new { Fiber.yield }

    wrapper.request_value(:value, thread_queue, fiber)

    error = StandardError.new("task failed")
    wrapper.mark_failed(error)

    msg = thread_queue.pop
    assert_instance_of Taski::Execution::FiberProtocol::ResumeError, msg
    assert_equal fiber, msg.fiber
    assert_equal error, msg.error
  end

  def test_multiple_waiters_all_notified_on_completion
    task_class = Class.new(Taski::Task) do
      exports :value
      def run
        @value = "shared_value"
      end
    end

    wrapper = create_wrapper(task_class)
    wrapper.mark_running

    queues = 3.times.map { Queue.new }
    fibers = 3.times.map { Fiber.new { Fiber.yield } }

    3.times { |i| wrapper.request_value(:value, queues[i], fibers[i]) }

    wrapper.task.run
    wrapper.mark_completed(wrapper.task.value)

    queues.each_with_index do |q, i|
      msg = q.pop
      assert_instance_of Taski::Execution::FiberProtocol::Resume, msg
      assert_equal fibers[i], msg.fiber
      assert_equal "shared_value", msg.value
    end
  end

  def test_concurrent_request_value_thread_safety
    task_class = Class.new(Taski::Task) do
      exports :value
      def run
        @value = "thread_safe"
      end
    end

    wrapper = create_wrapper(task_class)

    queues = 3.times.map { Queue.new }
    fibers = 3.times.map { Fiber.new { Fiber.yield } }
    results = Array.new(3)

    threads = 3.times.map { |i|
      Thread.new do
        results[i] = wrapper.request_value(:value, queues[i], fibers[i])
      end
    }
    threads.each(&:join)

    start_count = results.count { |r| r.is_a?(Taski::Execution::FiberProtocol::DepStarting) }
    wait_count = results.count { |r| r.is_a?(Taski::Execution::FiberProtocol::DepWaiting) }

    assert_equal 1, start_count, "Exactly one thread should get DepStarting"
    assert_equal 2, wait_count, "Other threads should get DepWaiting"
  end

  private

  def create_wrapper(task_class)
    task_instance = task_class.allocate
    task_instance.send(:initialize)
    wrapper = Taski::Execution::TaskWrapper.new(
      task_instance,
      registry: @registry,
      execution_facade: Taski::Execution::ExecutionFacade.new(root_task_class: task_class)
    )
    @registry.register(task_class, wrapper)
    wrapper
  end
end
