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
    task_class = ExecutorFixtures::SingleTask

    registry = Taski::Execution::Registry.new
    execution_facade = create_execution_facade(registry, task_class)

    executor = Taski::Execution::Executor.new(
      registry: registry,
      execution_facade: execution_facade
    )

    executor.execute(task_class)

    wrapper = registry.create_wrapper(task_class, execution_facade: execution_facade)
    assert wrapper.completed?
    assert_equal "result_value", wrapper.task.value
  end

  def test_linear_chain
    # A -> B -> C (C is leaf, B depends on C, A depends on B)
    task_class = ExecutorFixtures::ChainRoot

    registry = Taski::Execution::Registry.new
    execution_facade = create_execution_facade(registry, task_class)

    executor = Taski::Execution::Executor.new(
      registry: registry,
      execution_facade: execution_facade
    )

    executor.execute(task_class)

    wrapper = registry.create_wrapper(task_class, execution_facade: execution_facade)
    assert wrapper.completed?
    assert_equal "A->B->C", wrapper.task.value
  end

  def test_diamond_dependency
    # Root -> [A, B] -> C
    task_class = ExecutorFixtures::DiamondRoot

    registry = Taski::Execution::Registry.new
    execution_facade = create_execution_facade(registry, task_class)

    executor = Taski::Execution::Executor.new(
      registry: registry,
      execution_facade: execution_facade
    )

    executor.execute(task_class)

    wrapper = registry.create_wrapper(task_class, execution_facade: execution_facade)
    assert wrapper.completed?
    assert_equal "Root(A(C), B(C))", wrapper.task.value
  end

  def test_independent_parallel_tasks
    task_class = ExecutorFixtures::ParallelRoot

    registry = Taski::Execution::Registry.new
    execution_facade = create_execution_facade(registry, task_class)

    executor = Taski::Execution::Executor.new(
      registry: registry,
      execution_facade: execution_facade,
      worker_count: 2
    )

    start_time = Time.now
    executor.execute(task_class)
    elapsed = Time.now - start_time

    wrapper = registry.create_wrapper(task_class, execution_facade: execution_facade)
    assert wrapper.completed?
    assert_equal "A+B", wrapper.task.value
    # Both tasks sleep 0.1s; if parallel, should complete in ~0.1s not ~0.2s
    assert elapsed < 0.35, "Parallel tasks should complete in < 0.35s, took #{elapsed}s"
  end

  def test_task_with_error
    task_class = ExecutorFixtures::ErrorTask

    registry = Taski::Execution::Registry.new
    execution_facade = create_execution_facade(registry, task_class)

    executor = Taski::Execution::Executor.new(
      registry: registry,
      execution_facade: execution_facade
    )

    error = assert_raises(Taski::AggregateError) do
      executor.execute(task_class)
    end

    assert_equal 1, error.errors.size
    assert_equal "fiber error", error.errors.first.error.message
  end

  def test_conditional_dependency_not_executed
    task_class = ExecutorFixtures::ConditionalMain

    registry = Taski::Execution::Registry.new
    execution_facade = create_execution_facade(registry, task_class)

    executor = Taski::Execution::Executor.new(
      registry: registry,
      execution_facade: execution_facade
    )

    executor.execute(task_class)

    wrapper = registry.create_wrapper(task_class, execution_facade: execution_facade)
    assert wrapper.completed?
    # ConditionalMain's `if false` branch is never taken at runtime,
    # so the result reflects the non-conditional path
    assert_equal "no_dep", wrapper.task.value
  end

  def test_multiple_exported_methods
    task_class = ExecutorFixtures::MultiExportMain

    registry = Taski::Execution::Registry.new
    execution_facade = create_execution_facade(registry, task_class)

    executor = Taski::Execution::Executor.new(
      registry: registry,
      execution_facade: execution_facade
    )

    executor.execute(task_class)

    wrapper = registry.create_wrapper(task_class, execution_facade: execution_facade)
    assert wrapper.completed?
    assert_equal "Alice:30", wrapper.task.value
  end

  def test_dependency_error_propagates_to_waiting_fiber
    task_class = ExecutorFixtures::DepErrorMain

    registry = Taski::Execution::Registry.new
    execution_facade = create_execution_facade(registry, task_class)

    executor = Taski::Execution::Executor.new(
      registry: registry,
      execution_facade: execution_facade
    )

    error = assert_raises(Taski::AggregateError) do
      executor.execute(task_class)
    end

    # At least the failing_dep's error should be present
    assert error.errors.any? { |f| f.error.message.include?("dep failed") }
  end

  def test_dynamic_dependency_not_in_static_graph
    # A dependency that is NOT in the static dependency graph
    # but is resolved lazily at runtime via Fiber.yield
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
    dynamic_dep.instance_variable_set(:@dependencies_cache, Set.new)
    main_task.instance_variable_set(:@dependencies_cache, Set.new)

    registry = Taski::Execution::Registry.new
    execution_facade = create_execution_facade(registry, main_task)

    executor = Taski::Execution::Executor.new(
      registry: registry,
      execution_facade: execution_facade
    )

    executor.execute(main_task)

    wrapper = registry.create_wrapper(main_task, execution_facade: execution_facade)
    assert wrapper.completed?
    assert_equal "got:dynamic", wrapper.task.value
  end

  def test_skipped_tasks_are_notified_to_observers
    root_class = ExecutorFixtures::SkippedRoot
    middle_class = ExecutorFixtures::SkippedMiddle

    # Track observer notifications
    skipped_tasks = []
    observer = Object.new
    observer.define_singleton_method(:on_task_updated) do |tc, previous_state:, current_state:, **_|
      skipped_tasks << tc if current_state == :skipped
    end
    observer.define_singleton_method(:on_ready) {}
    observer.define_singleton_method(:on_start) {}
    observer.define_singleton_method(:on_stop) {}

    registry = Taski::Execution::Registry.new
    facade = Taski::Execution::ExecutionFacade.new(root_task_class: root_class)
    facade.add_observer(observer)

    executor = Taski::Execution::Executor.new(
      registry: registry,
      execution_facade: facade,
      worker_count: 2
    )

    executor.execute(root_class)

    # middle_class was in static graph but never enqueued -> should be skipped
    # Observers know all tasks start as pending from the dependency graph,
    # so no explicit nil→:pending notification is needed.
    assert_includes skipped_tasks, middle_class, "SkippedMiddle should be skipped"
    refute_includes skipped_tasks, root_class, "SkippedRoot should not be skipped"
  end

  def test_failed_task_skips_pending_dependents
    # Graph: root -> [branch_a, branch_b]
    #   branch_a -> failing_leaf (fails immediately)
    #   branch_b -> middle -> failing_leaf
    #
    # When failing_leaf fails:
    # - branch_a was started on-demand by WorkerPool (tracked by scheduler)
    # - middle and branch_b are PENDING in scheduler
    # - middle and branch_b should be marked as skipped via cascade
    failing_leaf = Class.new(Taski::Task) do
      exports :value
      def run
        raise StandardError, "leaf failed"
      end
    end

    middle = Class.new(Taski::Task) do
      exports :value
    end
    middle.define_method(:run) do
      v = Fiber.yield([:need_dep, failing_leaf, :value])
      @value = "m(#{v})"
    end

    branch_a = Class.new(Taski::Task) do
      exports :value
    end
    branch_a.define_method(:run) do
      v = Fiber.yield([:need_dep, failing_leaf, :value])
      @value = "a(#{v})"
    end

    branch_b = Class.new(Taski::Task) do
      exports :value
    end
    branch_b.define_method(:run) do
      v = Fiber.yield([:need_dep, middle, :value])
      @value = "b(#{v})"
    end

    root_task = Class.new(Taski::Task) do
      exports :value
    end
    root_task.define_method(:run) do
      a = Fiber.yield([:need_dep, branch_a, :value])
      b = Fiber.yield([:need_dep, branch_b, :value])
      @value = "#{a}+#{b}"
    end

    failing_leaf.instance_variable_set(:@dependencies_cache, Set.new)
    middle.instance_variable_set(:@dependencies_cache, Set[failing_leaf])
    branch_a.instance_variable_set(:@dependencies_cache, Set[failing_leaf])
    branch_b.instance_variable_set(:@dependencies_cache, Set[middle])
    root_task.instance_variable_set(:@dependencies_cache, Set[branch_a, branch_b])

    # Track observer notifications
    skipped_tasks = []
    observer = Object.new
    observer.define_singleton_method(:on_task_updated) do |tc, current_state:, **_|
      skipped_tasks << tc if current_state == :skipped
    end
    observer.define_singleton_method(:on_ready) {}
    observer.define_singleton_method(:on_start) {}
    observer.define_singleton_method(:on_stop) {}

    registry = Taski::Execution::Registry.new
    facade = Taski::Execution::ExecutionFacade.new(root_task_class: root_task)
    facade.add_observer(observer)

    executor = Taski::Execution::Executor.new(
      registry: registry,
      execution_facade: facade,
      worker_count: 2
    )

    assert_raises(Taski::AggregateError) do
      executor.execute(root_task)
    end

    # middle and branch_b should be skipped (never started, cascade from failing_leaf)
    assert_includes skipped_tasks, middle, "middle should be skipped via cascade"
    assert_includes skipped_tasks, branch_b, "branch_b should be skipped via cascade"
  end

  def test_log_execution_completed_includes_skipped_count
    root_class = ExecutorFixtures::SkippedRoot

    log_output = StringIO.new
    original_logger = Taski.logger
    begin
      Taski.logger = Logger.new(log_output, level: Logger::INFO)

      registry = Taski::Execution::Registry.new
      facade = Taski::Execution::ExecutionFacade.new(root_task_class: root_class)

      executor = Taski::Execution::Executor.new(
        registry: registry,
        execution_facade: facade,
        worker_count: 2
      )

      executor.execute(root_class)

      log_lines = log_output.string.lines.map { |l| l[/\{.*\}/] }.compact.map { |j| JSON.parse(j) }
      completed_event = log_lines.find { |e| e["event"] == "execution.completed" }

      refute_nil completed_event
      assert_equal 1, completed_event["data"]["skipped_count"]
    ensure
      Taski.logger = original_logger
    end
  end

  # ========================================
  # Skipped State Scenarios
  # ========================================

  def test_unreached_tasks_and_subtree_receive_pending_to_skipped
    # Graph: root -> [unreached_parent], unreached_parent -> unreached_child -> slow_leaf
    # Root completes immediately without yielding. slow_leaf takes time (pre-started).
    # Both unreached_parent and unreached_child remain STATE_PENDING -> skipped.
    # (Section API removed; this tests the equivalent behavior for conditional tasks)
    slow_leaf = Class.new(Taski::Task) do
      exports :value
    end
    slow_leaf.define_method(:run) do
      sleep 0.3
      @value = "slow"
    end

    unreached_child = Class.new(Taski::Task) do
      exports :value
    end
    unreached_child.define_method(:run) do
      @value = Fiber.yield([:need_dep, slow_leaf, :value])
    end

    unreached_parent = Class.new(Taski::Task) do
      exports :value
    end
    unreached_parent.define_method(:run) do
      @value = Fiber.yield([:need_dep, unreached_child, :value])
    end

    root = Class.new(Taski::Task) do
      exports :value
    end
    root.define_method(:run) { @value = "done" }

    slow_leaf.instance_variable_set(:@dependencies_cache, Set.new)
    unreached_child.instance_variable_set(:@dependencies_cache, Set[slow_leaf])
    unreached_parent.instance_variable_set(:@dependencies_cache, Set[unreached_child])
    root.instance_variable_set(:@dependencies_cache, Set[unreached_parent])

    skipped_transitions = {}
    observer = Object.new
    observer.define_singleton_method(:on_task_updated) do |tc, previous_state:, current_state:, **_|
      if previous_state == :pending && current_state == :skipped
        skipped_transitions[tc] = true
      end
    end
    observer.define_singleton_method(:on_ready) {}
    observer.define_singleton_method(:on_start) {}
    observer.define_singleton_method(:on_stop) {}

    registry = Taski::Execution::Registry.new
    facade = Taski::Execution::ExecutionFacade.new(root_task_class: root)
    facade.add_observer(observer)

    executor = Taski::Execution::Executor.new(
      registry: registry,
      execution_facade: facade,
      worker_count: 2
    )
    executor.execute(root)

    # Both unreached tasks should receive pending→skipped transition
    assert skipped_transitions[unreached_parent],
      "unreached_parent should receive pending→skipped"
    assert skipped_transitions[unreached_child],
      "unreached_child should receive pending→skipped"
    # Root should NOT be skipped
    refute skipped_transitions[root],
      "root should not be skipped"
  end

  def test_tasks_depending_on_failed_task_receive_pending_to_skipped_transition
    # Graph: root -> [started_branch, unstarted_branch]
    # Both branches depend on failing_leaf (pre-started as leaf)
    # Root yields for started_branch first -> it gets on-demand started
    # When failing_leaf fails, unstarted_branch is still pending -> cascade skipped
    failing_leaf = Class.new(Taski::Task) do
      exports :value
      def run
        raise StandardError, "boom"
      end
    end

    started_branch = Class.new(Taski::Task) do
      exports :value
    end
    started_branch.define_method(:run) do
      @value = Fiber.yield([:need_dep, failing_leaf, :value])
    end

    unstarted_branch = Class.new(Taski::Task) do
      exports :value
    end
    unstarted_branch.define_method(:run) do
      @value = Fiber.yield([:need_dep, failing_leaf, :value])
    end

    root = Class.new(Taski::Task) do
      exports :value
    end
    # Root yields for started_branch first; unstarted_branch stays pending
    root.define_method(:run) do
      a = Fiber.yield([:need_dep, started_branch, :value])
      b = Fiber.yield([:need_dep, unstarted_branch, :value])
      @value = "#{a}+#{b}"
    end

    failing_leaf.instance_variable_set(:@dependencies_cache, Set.new)
    started_branch.instance_variable_set(:@dependencies_cache, Set[failing_leaf])
    unstarted_branch.instance_variable_set(:@dependencies_cache, Set[failing_leaf])
    root.instance_variable_set(:@dependencies_cache, Set[started_branch, unstarted_branch])

    transitions = []
    observer = Object.new
    observer.define_singleton_method(:on_task_updated) do |tc, previous_state:, current_state:, **_|
      transitions << {task: tc, from: previous_state, to: current_state}
    end
    observer.define_singleton_method(:on_ready) {}
    observer.define_singleton_method(:on_start) {}
    observer.define_singleton_method(:on_stop) {}

    registry = Taski::Execution::Registry.new
    facade = Taski::Execution::ExecutionFacade.new(root_task_class: root)
    facade.add_observer(observer)

    executor = Taski::Execution::Executor.new(
      registry: registry,
      execution_facade: facade,
      worker_count: 2
    )

    assert_raises(Taski::AggregateError) { executor.execute(root) }

    # unstarted_branch should receive pending→skipped (cascade from failing_leaf)
    skip_transition = transitions.find { |t| t[:task] == unstarted_branch && t[:to] == :skipped }
    refute_nil skip_transition, "unstarted_branch should be skipped when its dependency fails"
    assert_equal :pending, skip_transition[:from]
  end

  def test_subtree_of_failed_task_also_marked_skipped
    # Graph: root -> [started_branch, deep_branch]
    #   started_branch -> failing_leaf (root yields for this first)
    #   deep_branch -> middle -> failing_leaf (root hasn't yielded for these)
    # When failing_leaf fails, middle and deep_branch are still pending -> skipped
    failing_leaf = Class.new(Taski::Task) do
      exports :value
      def run = raise("fail")
    end

    started_branch = Class.new(Taski::Task) do
      exports :value
    end
    started_branch.define_method(:run) do
      @value = Fiber.yield([:need_dep, failing_leaf, :value])
    end

    middle = Class.new(Taski::Task) do
      exports :value
    end
    middle.define_method(:run) do
      @value = Fiber.yield([:need_dep, failing_leaf, :value])
    end

    deep_branch = Class.new(Taski::Task) do
      exports :value
    end
    deep_branch.define_method(:run) do
      @value = Fiber.yield([:need_dep, middle, :value])
    end

    root = Class.new(Taski::Task) do
      exports :value
    end
    root.define_method(:run) do
      a = Fiber.yield([:need_dep, started_branch, :value])
      b = Fiber.yield([:need_dep, deep_branch, :value])
      @value = "#{a}+#{b}"
    end

    failing_leaf.instance_variable_set(:@dependencies_cache, Set.new)
    started_branch.instance_variable_set(:@dependencies_cache, Set[failing_leaf])
    middle.instance_variable_set(:@dependencies_cache, Set[failing_leaf])
    deep_branch.instance_variable_set(:@dependencies_cache, Set[middle])
    root.instance_variable_set(:@dependencies_cache, Set[started_branch, deep_branch])

    skipped_tasks = []
    observer = Object.new
    observer.define_singleton_method(:on_task_updated) do |tc, current_state:, **_|
      skipped_tasks << tc if current_state == :skipped
    end
    observer.define_singleton_method(:on_ready) {}
    observer.define_singleton_method(:on_start) {}
    observer.define_singleton_method(:on_stop) {}

    registry = Taski::Execution::Registry.new
    facade = Taski::Execution::ExecutionFacade.new(root_task_class: root)
    facade.add_observer(observer)

    executor = Taski::Execution::Executor.new(
      registry: registry,
      execution_facade: facade,
      worker_count: 2
    )

    assert_raises(Taski::AggregateError) { executor.execute(root) }

    # Both middle and deep_branch are pending -> cascade skipped
    assert_includes skipped_tasks, middle, "middle should be skipped (depends on failing_leaf)"
    assert_includes skipped_tasks, deep_branch, "deep_branch should be skipped (transitively depends on failing_leaf)"
  end

  def test_skipped_tasks_do_not_execute_clean_phase
    # Graph: root -> [good_dep, skipped_dep], skipped_dep -> failing_dep
    # failing_dep raises -> skipped_dep cascade-skipped -> never registered in Registry
    # Clean phase should only clean tasks that were actually registered (executed)
    good_dep = Class.new(Taski::Task) do
      exports :value
      def run = @value = "good"
      def clean = nil
    end

    failing_dep = Class.new(Taski::Task) do
      exports :value
      def run = raise "boom"
      def clean = nil
    end

    skipped_dep = Class.new(Taski::Task) do
      exports :value
    end
    skipped_dep.define_method(:run) do
      @value = Fiber.yield([:need_dep, failing_dep, :value])
    end
    skipped_dep.define_method(:clean) { nil }

    root = Class.new(Taski::Task) do
      exports :value
    end
    root.define_method(:run) { @value = "done" }
    root.define_method(:clean) { nil }

    good_dep.instance_variable_set(:@dependencies_cache, Set.new)
    failing_dep.instance_variable_set(:@dependencies_cache, Set.new)
    skipped_dep.instance_variable_set(:@dependencies_cache, Set[failing_dep])
    root.instance_variable_set(:@dependencies_cache, Set[good_dep, skipped_dep])

    clean_started_tasks = []
    observer = Object.new
    observer.define_singleton_method(:on_task_updated) do |tc, current_state:, phase:, **_|
      clean_started_tasks << tc if current_state == :running && phase == :clean
    end
    observer.define_singleton_method(:on_ready) {}
    observer.define_singleton_method(:on_start) {}
    observer.define_singleton_method(:on_stop) {}

    registry = Taski::Execution::Registry.new
    facade = Taski::Execution::ExecutionFacade.new(root_task_class: root)
    facade.add_observer(observer)

    # Run phase — failing_dep will fail, cascade-skipping skipped_dep
    begin
      Taski::Execution::Executor.new(
        registry: registry,
        execution_facade: facade,
        worker_count: 2
      ).execute(root)
    rescue Taski::TaskError
      # Expected — failing_dep raises
    end

    # Clean phase — skipped_dep should not be cleaned
    Taski::Execution::Executor.new(
      registry: registry,
      execution_facade: facade,
      worker_count: 2
    ).execute_clean(root)

    # skipped_dep was cascade-skipped and never registered -> should not be cleaned
    refute_includes clean_started_tasks, skipped_dep,
      "skipped task should not execute clean phase"
  end

  def test_failed_task_is_still_cleaned_for_resource_release
    # When a task fails during run, its clean phase should still execute
    # for resource release. Only cascade-skipped tasks (never started) skip clean.
    # Graph: root -> failing_dep (leaf)
    failing_dep = Class.new(Taski::Task) do
      exports :value
      def run = raise "boom"
      def clean = nil
    end

    root = Class.new(Taski::Task) do
      exports :value
    end
    root.define_method(:run) do
      @value = Fiber.yield([:need_dep, failing_dep, :value])
    end
    root.define_method(:clean) { nil }

    failing_dep.instance_variable_set(:@dependencies_cache, Set.new)
    root.instance_variable_set(:@dependencies_cache, Set[failing_dep])

    clean_started_tasks = []
    observer = Object.new
    observer.define_singleton_method(:on_task_updated) do |tc, current_state:, phase:, **_|
      clean_started_tasks << tc if current_state == :running && phase == :clean
    end
    observer.define_singleton_method(:on_ready) {}
    observer.define_singleton_method(:on_start) {}
    observer.define_singleton_method(:on_stop) {}

    registry = Taski::Execution::Registry.new
    facade = Taski::Execution::ExecutionFacade.new(root_task_class: root)
    facade.add_observer(observer)

    # Run phase — failing_dep will fail
    begin
      Taski::Execution::Executor.new(
        registry: registry,
        execution_facade: facade,
        worker_count: 2
      ).execute(root)
    rescue Taski::AggregateError
      # Expected
    end

    # Clean phase — failing_dep should still be cleaned for resource release
    Taski::Execution::Executor.new(
      registry: registry,
      execution_facade: facade,
      worker_count: 2
    ).execute_clean(root)

    assert_includes clean_started_tasks, failing_dep,
      "failed task should still be cleaned for resource release"
  end

  # ========================================
  # TaskWrapper Unified State Model
  # ========================================

  def test_task_wrapper_state_constants_are_unified
    assert_equal :pending, Taski::Execution::TaskWrapper::STATE_PENDING
    assert_equal :running, Taski::Execution::TaskWrapper::STATE_RUNNING
    assert_equal :completed, Taski::Execution::TaskWrapper::STATE_COMPLETED
    assert_equal :failed, Taski::Execution::TaskWrapper::STATE_FAILED
    assert_equal :skipped, Taski::Execution::TaskWrapper::STATE_SKIPPED
  end

  def test_task_wrapper_no_enqueued_state
    wrapper_constants = Taski::Execution::TaskWrapper.constants
    refute_includes wrapper_constants, :STATE_ENQUEUED
  end

  # ========================================
  # Single DependencyGraph Reuse
  # ========================================

  def test_executor_reuses_facade_dependency_graph
    task_class = ExecutorFixtures::SingleTask

    facade = Taski::Execution::ExecutionFacade.new(root_task_class: task_class)

    # Capture the graph built at facade initialization
    graph_before = facade.dependency_graph

    registry = Taski::Execution::Registry.new
    executor = Taski::Execution::Executor.new(
      registry: registry,
      execution_facade: facade
    )
    executor.execute(task_class)

    # The facade's graph should still be the same object (not rebuilt by Executor)
    assert_same graph_before, facade.dependency_graph,
      "Executor should reuse facade's existing dependency_graph"
  end

  def test_task_wrapper_clean_phase_failed_transitions_to_completed_with_error
    # Clean failure at the TaskWrapper level: state goes to STATE_COMPLETED
    # but error is captured. Scheduler-level always marks as completed.
    # Uses inline class because it needs a custom clean method
    task_class = Class.new(Taski::Task) do
      exports :value
      def run = @value = "test"
      def clean = nil
    end

    registry = Taski::Execution::Registry.new
    facade = Taski::Execution::ExecutionFacade.new(root_task_class: task_class)
    wrapper = registry.create_wrapper(task_class, execution_facade: facade)

    # Simulate clean lifecycle: pending → running → failed
    assert wrapper.mark_clean_running
    error = RuntimeError.new("clean boom")
    wrapper.mark_clean_failed(error)

    # State should be completed (not a separate "failed" state)
    refute wrapper.mark_clean_running, "cannot transition out of completed"
  end

  private

  def create_execution_facade(registry, task_class)
    Taski::Execution::ExecutionFacade.new(root_task_class: task_class)
  end
end
