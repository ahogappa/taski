# frozen_string_literal: true

require "test_helper"

class TestWorkerPool < Minitest::Test
  def setup
    Taski::Task.reset! if defined?(Taski::Task)
  end

  def test_worker_pool_initialization
    registry = Taski::Execution::Registry.new
    pool = Taski::Execution::WorkerPool.new(registry: registry, worker_count: 2) { |_task, _wrapper| }

    assert_kind_of Queue, pool.execution_queue
  end

  def test_worker_pool_enqueue_and_execute
    registry = Taski::Execution::Registry.new
    executed_tasks = []
    mutex = Mutex.new

    pool = Taski::Execution::WorkerPool.new(registry: registry, worker_count: 2) do |task_class, _wrapper|
      mutex.synchronize { executed_tasks << task_class }
    end

    task_class = Class.new(Taski::Task) do
      exports :value
      def run
        @value = "test"
      end
    end

    task_instance = task_class.allocate
    task_instance.send(:initialize)
    wrapper = Taski::Execution::TaskWrapper.new(task_instance, registry: registry)
    wrapper.mark_running

    pool.start
    pool.enqueue(task_class, wrapper)

    # Wait for execution
    sleep 0.1

    pool.shutdown

    assert_includes executed_tasks, task_class
  end

  def test_worker_pool_handles_callback_exception
    registry = Taski::Execution::Registry.new

    pool = Taski::Execution::WorkerPool.new(registry: registry, worker_count: 1) do |_task_class, _wrapper|
      raise "Callback error"
    end

    task_class = Class.new(Taski::Task) do
      exports :value
      def run
        @value = "test"
      end
    end

    task_instance = task_class.allocate
    task_instance.send(:initialize)
    wrapper = Taski::Execution::TaskWrapper.new(task_instance, registry: registry)
    wrapper.mark_running

    pool.start

    _out, err = capture_io do
      pool.enqueue(task_class, wrapper)
      sleep 0.1
    end

    pool.shutdown

    # Worker should have logged the error
    assert_match(/Unexpected error executing/, err)
  end

  def test_worker_pool_shutdown
    registry = Taski::Execution::Registry.new
    pool = Taski::Execution::WorkerPool.new(registry: registry, worker_count: 2) { |_task, _wrapper| }

    pool.start
    pool.shutdown

    # Should not hang - workers should have stopped
    assert true
  end
end
