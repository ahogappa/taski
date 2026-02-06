# frozen_string_literal: true

require "test_helper"

class TestWorkerPool < Minitest::Test
  def setup
    Taski::Task.reset! if defined?(Taski::Task)
    @registry = Taski::Execution::Registry.new
    @execution_context = Taski::Execution::ExecutionContext.new
    @shared_state = Taski::Execution::SharedState.new
  end

  def test_single_task_execution_no_deps
    task_class = Class.new(Taski::Task) do
      exports :value
      def run
        @value = "hello"
      end
    end

    completion_queue = Queue.new
    pool = Taski::Execution::WorkerPool.new(
      shared_state: @shared_state,
      registry: @registry,
      execution_context: @execution_context,
      worker_count: 1,
      completion_queue: completion_queue
    )

    wrapper = create_wrapper(task_class)
    @shared_state.register(task_class, wrapper)

    pool.start
    pool.enqueue(task_class, wrapper)

    event = completion_queue.pop
    pool.shutdown

    assert_equal task_class, event[:task_class]
    assert_nil event[:error]
    assert wrapper.completed?
    assert_equal "hello", wrapper.task.value
  end

  def test_two_independent_tasks_run_in_parallel
    task_a = Class.new(Taski::Task) do
      exports :value
      def run
        sleep 0.1
        @value = "A"
      end
    end

    task_b = Class.new(Taski::Task) do
      exports :value
      def run
        sleep 0.1
        @value = "B"
      end
    end

    completion_queue = Queue.new
    pool = Taski::Execution::WorkerPool.new(
      shared_state: @shared_state,
      registry: @registry,
      execution_context: @execution_context,
      worker_count: 2,
      completion_queue: completion_queue
    )

    wrapper_a = create_wrapper(task_a)
    wrapper_b = create_wrapper(task_b)
    @shared_state.register(task_a, wrapper_a)
    @shared_state.register(task_b, wrapper_b)

    pool.start

    start_time = Time.now
    pool.enqueue(task_a, wrapper_a)
    pool.enqueue(task_b, wrapper_b)

    # Wait for both completions
    2.times { completion_queue.pop }
    elapsed = Time.now - start_time
    pool.shutdown

    assert wrapper_a.completed?
    assert wrapper_b.completed?
    # Should complete in ~0.1s (parallel), not ~0.2s (sequential)
    assert elapsed < 0.35, "Parallel execution should complete in < 0.35s, took #{elapsed}s"
  end

  def test_task_with_dependency_resolved_locally
    # TaskDep has no deps, TaskMain depends on TaskDep.value
    task_dep = Class.new(Taski::Task) do
      exports :value
      def run
        @value = "dep_result"
      end
    end

    task_main = Class.new(Taski::Task) do
      exports :result
    end

    # We need to define run with access to task_dep
    task_main.define_method(:run) do
      # Simulate Fiber.yield for dependency
      @result = "main_got_#{Fiber.yield([:need_dep, task_dep, :value])}"
    end

    completion_queue = Queue.new
    pool = Taski::Execution::WorkerPool.new(
      shared_state: @shared_state,
      registry: @registry,
      execution_context: @execution_context,
      worker_count: 1,
      completion_queue: completion_queue
    )

    wrapper_main = create_wrapper(task_main)
    wrapper_dep = create_wrapper(task_dep)
    @shared_state.register(task_main, wrapper_main)
    @shared_state.register(task_dep, wrapper_dep)

    pool.start
    pool.enqueue(task_main, wrapper_main)

    # Should complete both tasks (dep started locally)
    events = []
    2.times { events << completion_queue.pop }
    pool.shutdown

    completed_classes = events.map { |e| e[:task_class] }
    assert_includes completed_classes, task_dep
    assert_includes completed_classes, task_main

    assert wrapper_dep.completed?
    assert wrapper_main.completed?
    assert_equal "dep_result", wrapper_dep.task.value
    assert_equal "main_got_dep_result", wrapper_main.task.result
  end

  def test_task_with_dependency_resolved_cross_thread
    task_dep = Class.new(Taski::Task) do
      exports :value
      def run
        sleep 0.05
        @value = "cross_thread_result"
      end
    end

    task_main = Class.new(Taski::Task) do
      exports :result
    end

    task_main.define_method(:run) do
      @result = "got_#{Fiber.yield([:need_dep, task_dep, :value])}"
    end

    completion_queue = Queue.new
    pool = Taski::Execution::WorkerPool.new(
      shared_state: @shared_state,
      registry: @registry,
      execution_context: @execution_context,
      worker_count: 2,
      completion_queue: completion_queue
    )

    wrapper_dep = create_wrapper(task_dep)
    wrapper_main = create_wrapper(task_main)
    @shared_state.register(task_dep, wrapper_dep)
    @shared_state.register(task_main, wrapper_main)

    pool.start

    # Start dep on one thread and main on another
    # Main will yield for dep, dep will run on another thread
    pool.enqueue(task_dep, wrapper_dep)
    pool.enqueue(task_main, wrapper_main)

    events = []
    2.times { events << completion_queue.pop }
    pool.shutdown

    assert wrapper_dep.completed?
    assert wrapper_main.completed?
    assert_equal "got_cross_thread_result", wrapper_main.task.result
  end

  def test_shutdown_stops_all_threads
    completion_queue = Queue.new
    pool = Taski::Execution::WorkerPool.new(
      shared_state: @shared_state,
      registry: @registry,
      execution_context: @execution_context,
      worker_count: 3,
      completion_queue: completion_queue
    )

    pool.start
    pool.shutdown

    # All threads should have terminated
    # No errors, no hanging
  end

  def test_fiber_context_restored_on_cross_thread_resume
    # When a fiber is parked (waiting for a dependency on another thread),
    # the thread-local fiber context is cleared by teardown_fiber_context.
    # When the fiber is resumed via :resume command, the context must be
    # restored so the fiber sees the correct registry and execution context.
    context_seen_after_resume = Queue.new

    task_dep = Class.new(Taski::Task) do
      exports :value
      def run
        sleep 0.05
        @value = "dep_value"
      end
    end

    task_main = Class.new(Taski::Task) do
      exports :result
    end

    task_main.define_method(:run) do
      # This Fiber.yield will park the fiber if dep is not yet complete
      v = Fiber.yield([:need_dep, task_dep, :value])
      # After resume, check that fiber context is properly set
      context_seen_after_resume.push({
        fiber_context: Thread.current[:taski_fiber_context],
        has_registry: !Taski.current_registry.nil?
      })
      @result = "got:#{v}"
    end

    completion_queue = Queue.new
    pool = Taski::Execution::WorkerPool.new(
      shared_state: @shared_state,
      registry: @registry,
      execution_context: @execution_context,
      worker_count: 2,
      completion_queue: completion_queue
    )

    wrapper_dep = create_wrapper(task_dep)
    wrapper_main = create_wrapper(task_main)
    @shared_state.register(task_dep, wrapper_dep)
    @shared_state.register(task_main, wrapper_main)

    pool.start

    # Enqueue dep and main on separate threads (round-robin)
    pool.enqueue(task_dep, wrapper_dep)
    pool.enqueue(task_main, wrapper_main)

    events = []
    2.times { events << completion_queue.pop }
    pool.shutdown

    assert wrapper_main.completed?, "main task should complete"
    assert_equal "got:dep_value", wrapper_main.task.result

    # Verify fiber context was properly restored after cross-thread resume
    ctx = context_seen_after_resume.pop
    assert ctx[:fiber_context], "fiber context flag should be true after resume"
    assert ctx[:has_registry], "registry should be set after resume"
  end

  def test_output_capture_scoped_per_fiber
    # When a dependency runs on the same thread (start_dependency),
    # the output capture should be saved/restored so the parent fiber's
    # capture is reinstated when it resumes.
    captured_tasks = []
    stopped_tasks = []

    # Create a mock output capture to track start/stop calls
    mock_capture = Object.new
    mock_capture.define_singleton_method(:start_capture) { |tc| captured_tasks << tc }
    mock_capture.define_singleton_method(:stop_capture) { stopped_tasks << :stop }
    mock_capture.define_singleton_method(:recent_lines_for) { |_| [] }

    # Inject mock capture into execution context
    @execution_context.instance_variable_set(:@output_capture, mock_capture)

    task_dep = Class.new(Taski::Task) do
      exports :value
      def run
        @value = "dep"
      end
    end

    task_main = Class.new(Taski::Task) do
      exports :result
    end
    task_main.define_method(:run) do
      @result = "main:#{Fiber.yield([:need_dep, task_dep, :value])}"
    end

    completion_queue = Queue.new
    pool = Taski::Execution::WorkerPool.new(
      shared_state: @shared_state,
      registry: @registry,
      execution_context: @execution_context,
      worker_count: 1,
      completion_queue: completion_queue
    )

    wrapper_main = create_wrapper(task_main)
    wrapper_dep = create_wrapper(task_dep)
    @shared_state.register(task_main, wrapper_main)
    @shared_state.register(task_dep, wrapper_dep)

    pool.start
    pool.enqueue(task_main, wrapper_main)

    events = []
    2.times { events << completion_queue.pop }
    pool.shutdown

    assert wrapper_main.completed?
    assert_equal "main:dep", wrapper_main.task.result

    # Output capture should have been started for main_task, then dep_task,
    # and then re-started for main_task after dep completes
    assert_operator captured_tasks.size, :>=, 3,
      "Expected capture to start for main, dep, and main again (got #{captured_tasks.inspect})"

    # The last start_capture before main completes should be for main_task
    # (i.e., capture was restored after dep completed)
    main_starts = captured_tasks.select { |tc| tc == task_main }
    assert_operator main_starts.size, :>=, 2,
      "Expected main task capture to be started at least twice (initial + restore)"
  end

  def test_error_in_task_is_captured
    task_class = Class.new(Taski::Task) do
      exports :value
      def run
        raise StandardError, "task error"
      end
    end

    completion_queue = Queue.new
    pool = Taski::Execution::WorkerPool.new(
      shared_state: @shared_state,
      registry: @registry,
      execution_context: @execution_context,
      worker_count: 1,
      completion_queue: completion_queue
    )

    wrapper = create_wrapper(task_class)
    @shared_state.register(task_class, wrapper)

    pool.start
    pool.enqueue(task_class, wrapper)

    event = completion_queue.pop
    pool.shutdown

    assert_equal task_class, event[:task_class]
    assert_instance_of StandardError, event[:error]
    assert_equal "task error", event[:error].message
  end

  private

  def create_wrapper(task_class)
    task_instance = task_class.allocate
    task_instance.send(:initialize)
    wrapper = Taski::Execution::TaskWrapper.new(
      task_instance,
      registry: @registry,
      execution_context: @execution_context
    )
    @registry.register(task_class, wrapper)
    wrapper
  end
end
