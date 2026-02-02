# frozen_string_literal: true

require "test_helper"
require_relative "fixtures/parallel_tasks"

class TestScheduler < Minitest::Test
  def setup
    Taski::Task.reset! if defined?(Taski::Task)
  end

  def test_build_dependency_graph_single_task
    task = Class.new(Taski::Task) do
      exports :value
      def run
        @value = "test"
      end
    end

    scheduler = Taski::Execution::Scheduler.new
    scheduler.build_dependency_graph(task)

    refute scheduler.completed?(task)
  end

  def test_next_ready_tasks_returns_pending_tasks
    task = Class.new(Taski::Task) do
      exports :value
      def run
        @value = "test"
      end
    end

    scheduler = Taski::Execution::Scheduler.new
    scheduler.build_dependency_graph(task)

    ready = scheduler.next_ready_tasks

    assert_includes ready, task
  end

  def test_mark_enqueued_prevents_re_enqueueing
    task = Class.new(Taski::Task) do
      exports :value
      def run
        @value = "test"
      end
    end

    scheduler = Taski::Execution::Scheduler.new
    scheduler.build_dependency_graph(task)

    ready1 = scheduler.next_ready_tasks
    assert_includes ready1, task

    scheduler.mark_enqueued(task)

    ready2 = scheduler.next_ready_tasks
    refute_includes ready2, task
  end

  def test_mark_completed
    task = Class.new(Taski::Task) do
      exports :value
      def run
        @value = "test"
      end
    end

    scheduler = Taski::Execution::Scheduler.new
    scheduler.build_dependency_graph(task)

    scheduler.mark_enqueued(task)
    scheduler.mark_completed(task)

    assert scheduler.completed?(task)
  end

  def test_running_tasks_returns_true_when_tasks_enqueued
    task = Class.new(Taski::Task) do
      exports :value
      def run
        @value = "test"
      end
    end

    scheduler = Taski::Execution::Scheduler.new
    scheduler.build_dependency_graph(task)

    refute scheduler.running_tasks?

    scheduler.mark_enqueued(task)
    assert scheduler.running_tasks?

    scheduler.mark_completed(task)
    refute scheduler.running_tasks?
  end

  # ========================================
  # Clean Operation Tests
  # ========================================

  def test_build_reverse_dependency_graph_single_task
    # FixtureTaskA has no dependencies
    scheduler = Taski::Execution::Scheduler.new
    scheduler.build_reverse_dependency_graph(FixtureTaskA)

    refute scheduler.clean_completed?(FixtureTaskA)
  end

  def test_build_reverse_dependency_graph_creates_reverse_mappings
    # CleanTaskD -> CleanTaskC -> CleanTaskB -> CleanTaskA
    # Clean order should be: D first, then C, then B, then A
    scheduler = Taski::Execution::Scheduler.new
    scheduler.build_reverse_dependency_graph(CleanTaskD)

    # Only D should be ready (no tasks depend on D)
    ready = scheduler.next_ready_clean_tasks
    assert_includes ready, CleanTaskD
    refute_includes ready, CleanTaskC
    refute_includes ready, CleanTaskB
    refute_includes ready, CleanTaskA
  end

  def test_next_ready_clean_tasks_returns_root_first
    # FixtureTaskB -> FixtureTaskA
    # Clean order: B first, then A
    scheduler = Taski::Execution::Scheduler.new
    scheduler.build_reverse_dependency_graph(FixtureTaskB)

    ready = scheduler.next_ready_clean_tasks
    assert_includes ready, FixtureTaskB
    refute_includes ready, FixtureTaskA
  end

  def test_mark_clean_enqueued_prevents_re_enqueueing
    scheduler = Taski::Execution::Scheduler.new
    scheduler.build_reverse_dependency_graph(FixtureTaskA)

    ready1 = scheduler.next_ready_clean_tasks
    assert_includes ready1, FixtureTaskA

    scheduler.mark_clean_enqueued(FixtureTaskA)

    ready2 = scheduler.next_ready_clean_tasks
    refute_includes ready2, FixtureTaskA
  end

  def test_mark_clean_completed
    scheduler = Taski::Execution::Scheduler.new
    scheduler.build_reverse_dependency_graph(FixtureTaskA)

    scheduler.mark_clean_enqueued(FixtureTaskA)
    scheduler.mark_clean_completed(FixtureTaskA)

    assert scheduler.clean_completed?(FixtureTaskA)
  end

  def test_clean_order_is_reverse_of_run_order
    # FixtureTaskB -> FixtureTaskA
    # Run order: A first, then B
    # Clean order: B first, then A
    scheduler = Taski::Execution::Scheduler.new
    scheduler.build_reverse_dependency_graph(FixtureTaskB)

    # Step 1: Only B is ready to clean (no tasks depend on B)
    ready = scheduler.next_ready_clean_tasks
    assert_equal 1, ready.size
    assert_includes ready, FixtureTaskB

    # Step 2: Complete B's clean, now A becomes ready
    scheduler.mark_clean_enqueued(FixtureTaskB)
    scheduler.mark_clean_completed(FixtureTaskB)

    ready = scheduler.next_ready_clean_tasks
    assert_includes ready, FixtureTaskA
  end

  def test_running_clean_tasks_returns_true_when_clean_tasks_enqueued
    scheduler = Taski::Execution::Scheduler.new
    scheduler.build_reverse_dependency_graph(FixtureTaskA)

    refute scheduler.running_clean_tasks?

    scheduler.mark_clean_enqueued(FixtureTaskA)
    assert scheduler.running_clean_tasks?

    scheduler.mark_clean_completed(FixtureTaskA)
    refute scheduler.running_clean_tasks?
  end

  def test_parallel_clean_for_independent_tasks
    # ParallelTaskC -> [ParallelTaskA, ParallelTaskB]
    # A and B are independent, so they can clean in parallel after C
    scheduler = Taski::Execution::Scheduler.new
    scheduler.build_reverse_dependency_graph(ParallelTaskC)

    # Step 1: Only C is ready (depends on A and B, but nothing depends on C)
    ready = scheduler.next_ready_clean_tasks
    assert_equal 1, ready.size
    assert_includes ready, ParallelTaskC

    # Step 2: Complete C, A and B become ready in parallel
    scheduler.mark_clean_enqueued(ParallelTaskC)
    scheduler.mark_clean_completed(ParallelTaskC)

    ready = scheduler.next_ready_clean_tasks
    assert_equal 2, ready.size
    assert_includes ready, ParallelTaskA
    assert_includes ready, ParallelTaskB
  end

  def test_long_chain_clean_order
    # CleanTaskD -> CleanTaskC -> CleanTaskB -> CleanTaskA
    # Clean order: D, C, B, A
    scheduler = Taski::Execution::Scheduler.new
    scheduler.build_reverse_dependency_graph(CleanTaskD)

    # Step 1: D is ready
    ready = scheduler.next_ready_clean_tasks
    assert_equal [CleanTaskD], ready

    # Step 2: Complete D, C becomes ready
    scheduler.mark_clean_enqueued(CleanTaskD)
    scheduler.mark_clean_completed(CleanTaskD)
    ready = scheduler.next_ready_clean_tasks
    assert_equal [CleanTaskC], ready

    # Step 3: Complete C, B becomes ready
    scheduler.mark_clean_enqueued(CleanTaskC)
    scheduler.mark_clean_completed(CleanTaskC)
    ready = scheduler.next_ready_clean_tasks
    assert_equal [CleanTaskB], ready

    # Step 4: Complete B, A becomes ready
    scheduler.mark_clean_enqueued(CleanTaskB)
    scheduler.mark_clean_completed(CleanTaskB)
    ready = scheduler.next_ready_clean_tasks
    assert_equal [CleanTaskA], ready

    # Step 5: Complete A, no more tasks
    scheduler.mark_clean_enqueued(CleanTaskA)
    scheduler.mark_clean_completed(CleanTaskA)
    ready = scheduler.next_ready_clean_tasks
    assert_equal [], ready
  end

  # ========================================
  # Runtime Dependency Merging Tests
  # ========================================

  def test_merge_runtime_dependencies_recursively_adds_transitive_deps
    # Create task classes with explicit cached_dependencies
    # GrandchildTask - no dependencies
    grandchild_task = Class.new(Taski::Task) do
      exports :value
      def run
        @value = "grandchild"
      end
    end
    grandchild_task.define_singleton_method(:cached_dependencies) { Set.new }

    # ChildTask depends on GrandchildTask
    child_task = Class.new(Taski::Task) do
      exports :result
      def run
        @result = "child"
      end
    end
    # ChildTask depends on GrandchildTask (explicit)
    child_task.define_singleton_method(:cached_dependencies) { Set[grandchild_task] }

    # RuntimeSection - Section always returns empty cached_dependencies
    runtime_section = Class.new(Taski::Section) do
      interfaces :result
    end

    # RootTask depends on RuntimeSection (explicit)
    root_task = Class.new(Taski::Task) do
      exports :output
      def run
        @output = "root"
      end
    end
    root_task.define_singleton_method(:cached_dependencies) { Set[runtime_section] }

    scheduler = Taski::Execution::Scheduler.new
    scheduler.build_dependency_graph(root_task)
    scheduler.build_reverse_dependency_graph(root_task)

    # At this point: RootTask and RuntimeSection are in graph
    # ChildTask and GrandchildTask are NOT (Section has no static deps)
    task_states = scheduler.instance_variable_get(:@task_states)
    assert task_states.key?(root_task), "RootTask should be in task_states"
    assert task_states.key?(runtime_section), "RuntimeSection should be in task_states"
    refute task_states.key?(child_task), "ChildTask should NOT be in task_states before merge"
    refute task_states.key?(grandchild_task), "GrandchildTask should NOT be in task_states before merge"

    # Simulate runtime dependency: RuntimeSection → ChildTask
    runtime_deps = {runtime_section => Set[child_task]}
    scheduler.merge_runtime_dependencies(runtime_deps)

    # Re-fetch task_states after merge
    task_states = scheduler.instance_variable_get(:@task_states)

    # Verify ChildTask is in the graph
    assert task_states.key?(child_task), "ChildTask should be in task_states after merge"

    # Verify GrandchildTask (transitive dependency) is also in the graph
    assert task_states.key?(grandchild_task),
      "GrandchildTask (transitive dep) should be in task_states after merge"

    # Verify reverse dependencies for clean
    reverse_deps = scheduler.instance_variable_get(:@reverse_dependencies)
    assert reverse_deps.key?(grandchild_task),
      "GrandchildTask should have reverse_dependencies entry for clean"

    # Verify clean states
    clean_states = scheduler.instance_variable_get(:@clean_task_states)
    assert clean_states.key?(grandchild_task),
      "GrandchildTask should have clean_task_state for clean"
  end
end
