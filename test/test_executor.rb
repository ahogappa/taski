# frozen_string_literal: true

require "test_helper"
require_relative "fixtures/executor_tasks"
require "logger"
require "json"

class TestExecutor < Minitest::Test
  def setup
    Taski::Task.reset! if defined?(Taski::Task)
  end

  def test_single_task_no_deps
    registry = Taski::Execution::Registry.new
    execution_context = create_execution_context(registry)

    executor = Taski::Execution::Executor.new(
      registry: registry,
      execution_context: execution_context
    )

    executor.execute(ExecutorFixtures::SingleTask)

    wrapper = registry.get_task(ExecutorFixtures::SingleTask)
    assert wrapper.completed?
    assert_equal "result_value", wrapper.task.value
  end

  def test_linear_chain
    registry = Taski::Execution::Registry.new
    execution_context = create_execution_context(registry)

    executor = Taski::Execution::Executor.new(
      registry: registry,
      execution_context: execution_context
    )

    executor.execute(ExecutorFixtures::ChainRoot)

    wrapper_a = registry.get_task(ExecutorFixtures::ChainRoot)
    assert wrapper_a.completed?
    assert_equal "A->B->C", wrapper_a.task.value
  end

  def test_diamond_dependency
    registry = Taski::Execution::Registry.new
    execution_context = create_execution_context(registry)

    executor = Taski::Execution::Executor.new(
      registry: registry,
      execution_context: execution_context
    )

    executor.execute(ExecutorFixtures::DiamondRoot)

    wrapper = registry.get_task(ExecutorFixtures::DiamondRoot)
    assert wrapper.completed?
    assert_equal "Root(A(C), B(C))", wrapper.task.value
  end

  def test_independent_parallel_tasks
    registry = Taski::Execution::Registry.new
    execution_context = create_execution_context(registry)

    executor = Taski::Execution::Executor.new(
      registry: registry,
      execution_context: execution_context,
      worker_count: 2
    )

    start_time = Time.now
    executor.execute(ExecutorFixtures::ParallelRoot)
    elapsed = Time.now - start_time

    wrapper = registry.get_task(ExecutorFixtures::ParallelRoot)
    assert wrapper.completed?
    assert_equal "A+B", wrapper.task.value
    # Both tasks sleep 0.1s; if parallel, should complete in ~0.1s not ~0.2s
    assert elapsed < 0.35, "Parallel tasks should complete in < 0.35s, took #{elapsed}s"
  end

  def test_task_with_error
    registry = Taski::Execution::Registry.new
    execution_context = create_execution_context(registry)

    executor = Taski::Execution::Executor.new(
      registry: registry,
      execution_context: execution_context
    )

    error = assert_raises(Taski::AggregateError) do
      executor.execute(ExecutorFixtures::ErrorTask)
    end

    assert_equal 1, error.errors.size
    assert_equal "fiber error", error.errors.first.error.message
  end

  def test_conditional_dependency_not_executed
    registry = Taski::Execution::Registry.new
    execution_context = create_execution_context(registry)

    executor = Taski::Execution::Executor.new(
      registry: registry,
      execution_context: execution_context
    )

    executor.execute(ExecutorFixtures::ConditionalMain)

    wrapper = registry.get_task(ExecutorFixtures::ConditionalMain)
    assert wrapper.completed?
    # ConditionalMain's `if false` branch is never taken at runtime,
    # so the result reflects the non-conditional path
    assert_equal "no_dep", wrapper.task.value
  end

  def test_multiple_exported_methods
    registry = Taski::Execution::Registry.new
    execution_context = create_execution_context(registry)

    executor = Taski::Execution::Executor.new(
      registry: registry,
      execution_context: execution_context
    )

    executor.execute(ExecutorFixtures::MultiExportMain)

    wrapper = registry.get_task(ExecutorFixtures::MultiExportMain)
    assert wrapper.completed?
    assert_equal "Alice:30", wrapper.task.value
  end

  def test_dependency_error_propagates_to_waiting_fiber
    registry = Taski::Execution::Registry.new
    execution_context = create_execution_context(registry)

    executor = Taski::Execution::Executor.new(
      registry: registry,
      execution_context: execution_context
    )

    error = assert_raises(Taski::AggregateError) do
      executor.execute(ExecutorFixtures::DepErrorMain)
    end

    # At least the failing_dep's error should be present
    assert error.errors.any? { |f| f.error.message.include?("dep failed") }
  end

  def test_dynamic_dependency_not_in_static_graph
    # A dependency that is NOT in the static dependency graph
    # but is resolved lazily at runtime via Fiber.yield.
    # Intentionally inline: fixture would make static analysis detect it.
    dynamic_dep = Class.new(Taski::Task) do
      exports :value
      def run
        @value = "dynamic"
      end
    end

    main_task = Class.new(Taski::Task) do
      exports :value
    end
    main_task.define_method(:run) do
      v = Fiber.yield([:need_dep, dynamic_dep, :value])
      @value = "got:#{v}"
    end

    # dynamic_dep is NOT in main_task's static dependencies
    dynamic_dep.define_singleton_method(:cached_dependencies) { Set.new }
    main_task.define_singleton_method(:cached_dependencies) { Set.new }

    registry = Taski::Execution::Registry.new
    execution_context = create_execution_context(registry)

    executor = Taski::Execution::Executor.new(
      registry: registry,
      execution_context: execution_context
    )

    executor.execute(main_task)

    wrapper = registry.get_task(main_task)
    assert wrapper.completed?
    assert_equal "got:dynamic", wrapper.task.value
  end

  def test_skipped_tasks_are_notified_to_observers
    # Track observer notifications
    skipped_tasks = []
    registered_tasks = []
    observer = Object.new
    observer.define_singleton_method(:register_task) { |tc| registered_tasks << tc }
    observer.define_singleton_method(:update_task) do |tc, state:, **_|
      skipped_tasks << tc if state == :skipped
    end
    observer.define_singleton_method(:set_root_task) { |_| }
    observer.define_singleton_method(:start) {}
    observer.define_singleton_method(:stop) {}

    registry = Taski::Execution::Registry.new
    context = Taski::Execution::ExecutionContext.new
    context.add_observer(observer)
    context.execution_trigger = ->(tc, reg) do
      Taski::Execution::Executor.new(
        registry: reg,
        execution_context: context,
        worker_count: 2
      ).execute(tc)
    end

    executor = Taski::Execution::Executor.new(
      registry: registry,
      execution_context: context,
      worker_count: 2
    )

    executor.execute(ExecutorFixtures::SkippedRoot)

    # SkippedMiddle was in static graph but never enqueued -> should be skipped
    assert_includes skipped_tasks, ExecutorFixtures::SkippedMiddle, "SkippedMiddle should be skipped"
    assert_includes registered_tasks, ExecutorFixtures::SkippedMiddle, "SkippedMiddle should be registered first"
    refute_includes skipped_tasks, ExecutorFixtures::SkippedRoot, "SkippedRoot should not be skipped"
  end

  def test_log_execution_completed_includes_skipped_count
    log_output = StringIO.new
    original_logger = Taski.logger
    begin
      Taski.logger = Logger.new(log_output, level: Logger::INFO)

      registry = Taski::Execution::Registry.new
      context = Taski::Execution::ExecutionContext.new
      context.add_observer(Taski::Logging::LoggerObserver.new)
      context.execution_trigger = ->(tc, reg) do
        Taski::Execution::Executor.new(
          registry: reg,
          execution_context: context,
          worker_count: 2
        ).execute(tc)
      end

      executor = Taski::Execution::Executor.new(
        registry: registry,
        execution_context: context,
        worker_count: 2
      )

      executor.execute(ExecutorFixtures::SkippedRoot)

      log_lines = log_output.string.lines.map { |l| l[/\{.*\}/] }.compact.map { |j| JSON.parse(j) }
      completed_event = log_lines.find { |e| e["event"] == "execution.completed" }

      refute_nil completed_event
      assert_equal 1, completed_event["data"]["skipped_count"]
    ensure
      Taski.logger = original_logger
    end
  end

  private

  def create_execution_context(registry)
    context = Taski::Execution::ExecutionContext.new
    context.execution_trigger = ->(task_class, reg) do
      Taski::Execution::Executor.new(
        registry: reg,
        execution_context: context
      ).execute(task_class)
    end
    context
  end
end
