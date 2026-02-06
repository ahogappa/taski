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
  # Skipped Task Classes Tests
  # ========================================

  def test_skipped_task_classes_returns_pending_tasks_after_execution
    # 3 tasks in graph, only 1 completed -> 2 are skipped
    task_a = Class.new(Taski::Task) do
      exports :value
      def run = @value = "a"
    end
    task_a.define_singleton_method(:cached_dependencies) { Set.new }

    task_b = Class.new(Taski::Task) do
      exports :value
      def run = @value = "b"
    end
    task_b.define_singleton_method(:cached_dependencies) { Set.new }

    task_c = Class.new(Taski::Task) do
      exports :value
      def run = @value = "c"
    end
    task_c.define_singleton_method(:cached_dependencies) { Set[task_a, task_b] }

    scheduler = Taski::Execution::Scheduler.new
    scheduler.build_dependency_graph(task_c)

    # Only complete task_a
    scheduler.mark_enqueued(task_a)
    scheduler.mark_completed(task_a)

    skipped = scheduler.skipped_task_classes
    assert_includes skipped, task_b
    assert_includes skipped, task_c
    refute_includes skipped, task_a
    assert_equal 2, skipped.size
  end

  def test_skipped_task_classes_returns_empty_when_all_completed
    task = Class.new(Taski::Task) do
      exports :value
      def run = @value = "test"
    end

    scheduler = Taski::Execution::Scheduler.new
    scheduler.build_dependency_graph(task)

    scheduler.mark_enqueued(task)
    scheduler.mark_completed(task)

    assert_empty scheduler.skipped_task_classes
  end

  def test_skipped_task_classes_does_not_include_enqueued_tasks
    task_a = Class.new(Taski::Task) do
      exports :value
      def run = @value = "a"
    end
    task_a.define_singleton_method(:cached_dependencies) { Set.new }

    task_b = Class.new(Taski::Task) do
      exports :value
      def run = @value = "b"
    end
    task_b.define_singleton_method(:cached_dependencies) { Set[task_a] }

    scheduler = Taski::Execution::Scheduler.new
    scheduler.build_dependency_graph(task_b)

    scheduler.mark_enqueued(task_a)

    skipped = scheduler.skipped_task_classes
    # task_a is enqueued (not pending), task_b is pending
    refute_includes skipped, task_a
    assert_includes skipped, task_b
  end
end
