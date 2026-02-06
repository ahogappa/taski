# frozen_string_literal: true

require "test_helper"

class TestFiberExecutor < Minitest::Test
  def setup
    Taski::Task.reset! if defined?(Taski::Task)
  end

  def test_single_task_no_deps
    task_class = Class.new(Taski::Task) do
      exports :value
      def run
        @value = "fiber_result"
      end
    end

    registry = Taski::Execution::Registry.new
    execution_context = create_execution_context(registry)

    executor = Taski::Execution::FiberExecutor.new(
      registry: registry,
      execution_context: execution_context
    )

    executor.execute(task_class)

    wrapper = registry.get_task(task_class)
    assert wrapper.completed?
    assert_equal "fiber_result", wrapper.task.value
  end

  def test_linear_chain
    # A -> B -> C (C is leaf, B depends on C, A depends on B)
    task_c = Class.new(Taski::Task) do
      exports :value
      def run
        @value = "C"
      end
    end

    task_b = Class.new(Taski::Task) do
      exports :value
    end
    task_b.define_method(:run) do
      @value = "B->#{Fiber.yield([:need_dep, task_c, :value])}"
    end

    task_a = Class.new(Taski::Task) do
      exports :value
    end
    task_a.define_method(:run) do
      @value = "A->#{Fiber.yield([:need_dep, task_b, :value])}"
    end

    # Set up static dependencies for the scheduler
    task_c.instance_variable_set(:@dependencies_cache, Set.new)
    task_b.instance_variable_set(:@dependencies_cache, Set[task_c])
    task_a.instance_variable_set(:@dependencies_cache, Set[task_b])

    registry = Taski::Execution::Registry.new
    execution_context = create_execution_context(registry)

    executor = Taski::Execution::FiberExecutor.new(
      registry: registry,
      execution_context: execution_context
    )

    executor.execute(task_a)

    wrapper_a = registry.get_task(task_a)
    assert wrapper_a.completed?
    assert_equal "A->B->C", wrapper_a.task.value
  end

  def test_diamond_dependency
    # Root -> [A, B] -> C
    task_c = Class.new(Taski::Task) do
      exports :value
      def run
        @value = "C"
      end
    end

    task_a = Class.new(Taski::Task) do
      exports :value
    end
    task_a.define_method(:run) do
      @value = "A(#{Fiber.yield([:need_dep, task_c, :value])})"
    end

    task_b = Class.new(Taski::Task) do
      exports :value
    end
    task_b.define_method(:run) do
      @value = "B(#{Fiber.yield([:need_dep, task_c, :value])})"
    end

    root_task = Class.new(Taski::Task) do
      exports :value
    end
    root_task.define_method(:run) do
      a = Fiber.yield([:need_dep, task_a, :value])
      b = Fiber.yield([:need_dep, task_b, :value])
      @value = "Root(#{a}, #{b})"
    end

    task_c.instance_variable_set(:@dependencies_cache, Set.new)
    task_a.instance_variable_set(:@dependencies_cache, Set[task_c])
    task_b.instance_variable_set(:@dependencies_cache, Set[task_c])
    root_task.instance_variable_set(:@dependencies_cache, Set[task_a, task_b])

    registry = Taski::Execution::Registry.new
    execution_context = create_execution_context(registry)

    executor = Taski::Execution::FiberExecutor.new(
      registry: registry,
      execution_context: execution_context
    )

    executor.execute(root_task)

    wrapper = registry.get_task(root_task)
    assert wrapper.completed?
    assert_equal "Root(A(C), B(C))", wrapper.task.value
  end

  def test_independent_parallel_tasks
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

    root_task = Class.new(Taski::Task) do
      exports :value
    end
    root_task.define_method(:run) do
      a = Fiber.yield([:need_dep, task_a, :value])
      b = Fiber.yield([:need_dep, task_b, :value])
      @value = "#{a}+#{b}"
    end

    task_a.instance_variable_set(:@dependencies_cache, Set.new)
    task_b.instance_variable_set(:@dependencies_cache, Set.new)
    root_task.instance_variable_set(:@dependencies_cache, Set[task_a, task_b])

    registry = Taski::Execution::Registry.new
    execution_context = create_execution_context(registry)

    executor = Taski::Execution::FiberExecutor.new(
      registry: registry,
      execution_context: execution_context,
      worker_count: 2
    )

    start_time = Time.now
    executor.execute(root_task)
    elapsed = Time.now - start_time

    wrapper = registry.get_task(root_task)
    assert wrapper.completed?
    assert_equal "A+B", wrapper.task.value
    # Both tasks sleep 0.1s; if parallel, should complete in ~0.1s not ~0.2s
    assert elapsed < 0.25, "Parallel tasks should complete in < 0.25s, took #{elapsed}s"
  end

  def test_task_with_error
    task_class = Class.new(Taski::Task) do
      exports :value
      def run
        raise StandardError, "fiber error"
      end
    end

    registry = Taski::Execution::Registry.new
    execution_context = create_execution_context(registry)

    executor = Taski::Execution::FiberExecutor.new(
      registry: registry,
      execution_context: execution_context
    )

    error = assert_raises(Taski::AggregateError) do
      executor.execute(task_class)
    end

    assert_equal 1, error.errors.size
    assert_equal "fiber error", error.errors.first.error.message
  end

  def test_conditional_dependency_not_executed
    # A task that conditionally depends on another task
    dep_task = Class.new(Taski::Task) do
      exports :value
      def run
        @value = "should_not_run"
      end
    end

    main_task = Class.new(Taski::Task) do
      exports :value
    end
    # Condition is false, so dep is NOT accessed via Fiber.yield
    main_task.define_method(:run) do
      if false # rubocop:disable Lint/LiteralAsCondition
        Fiber.yield([:need_dep, dep_task, :value])
      end
      @value = "no_dep"
    end

    main_task.instance_variable_set(:@dependencies_cache, Set.new)

    registry = Taski::Execution::Registry.new
    execution_context = create_execution_context(registry)

    executor = Taski::Execution::FiberExecutor.new(
      registry: registry,
      execution_context: execution_context
    )

    executor.execute(main_task)

    wrapper = registry.get_task(main_task)
    assert wrapper.completed?
    assert_equal "no_dep", wrapper.task.value

    # dep_task should NOT have been registered
    assert_raises(RuntimeError) { registry.get_task(dep_task) }
  end

  private

  def create_execution_context(registry)
    context = Taski::Execution::ExecutionContext.new
    context.execution_trigger = ->(task_class, reg) do
      Taski::Execution::FiberExecutor.new(
        registry: reg,
        execution_context: context
      ).execute(task_class)
    end
    context
  end
end
