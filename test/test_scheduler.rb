# frozen_string_literal: true

require "test_helper"
require_relative "fixtures/parallel_tasks"

class TestScheduler < Minitest::Test
  def setup
    Taski::Task.reset! if defined?(Taski::Task)
  end

  def test_load_graph_single_task
    task = Class.new(Taski::Task) do
      exports :value
      def run
        @value = "test"
      end
    end

    graph = Taski::StaticAnalysis::DependencyGraph.new.build_from_cached(task)
    scheduler = Taski::Execution::Scheduler.new
    scheduler.load_graph(graph, task)

    refute scheduler.completed?(task)
  end

  def test_load_graph_populates_task_states
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

    graph = Taski::StaticAnalysis::DependencyGraph.new.build_from_cached(task_b)
    scheduler = Taski::Execution::Scheduler.new
    scheduler.load_graph(graph, task_b)

    assert_equal 2, scheduler.task_count
  end

  def test_next_ready_tasks_returns_pending_tasks
    task = Class.new(Taski::Task) do
      exports :value
      def run
        @value = "test"
      end
    end

    graph = Taski::StaticAnalysis::DependencyGraph.new.build_from_cached(task)
    scheduler = Taski::Execution::Scheduler.new
    scheduler.load_graph(graph, task)

    ready = scheduler.next_ready_tasks

    assert_includes ready, task
  end

  def test_mark_running_prevents_re_selection
    task = Class.new(Taski::Task) do
      exports :value
      def run
        @value = "test"
      end
    end

    graph = Taski::StaticAnalysis::DependencyGraph.new.build_from_cached(task)
    scheduler = Taski::Execution::Scheduler.new
    scheduler.load_graph(graph, task)

    ready1 = scheduler.next_ready_tasks
    assert_includes ready1, task

    scheduler.mark_running(task)

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

    graph = Taski::StaticAnalysis::DependencyGraph.new.build_from_cached(task)
    scheduler = Taski::Execution::Scheduler.new
    scheduler.load_graph(graph, task)

    scheduler.mark_running(task)
    scheduler.mark_completed(task)

    assert scheduler.completed?(task)
  end

  def test_running_tasks_returns_true_when_tasks_running
    task = Class.new(Taski::Task) do
      exports :value
      def run
        @value = "test"
      end
    end

    graph = Taski::StaticAnalysis::DependencyGraph.new.build_from_cached(task)
    scheduler = Taski::Execution::Scheduler.new
    scheduler.load_graph(graph, task)

    refute scheduler.running_tasks?

    scheduler.mark_running(task)
    assert scheduler.running_tasks?

    scheduler.mark_completed(task)
    refute scheduler.running_tasks?
  end

  # ========================================
  # Clean Operation Tests
  # ========================================

  def test_build_reverse_dependency_graph_single_task
    # FixtureTaskA has no dependencies
    graph = Taski::StaticAnalysis::DependencyGraph.new.build_from_cached(FixtureTaskA)
    scheduler = Taski::Execution::Scheduler.new
    scheduler.load_graph(graph, FixtureTaskA)
    scheduler.build_reverse_dependency_graph

    refute scheduler.clean_completed?(FixtureTaskA)
  end

  def test_build_reverse_dependency_graph_creates_reverse_mappings
    # CleanTaskD -> CleanTaskC -> CleanTaskB -> CleanTaskA
    # Clean order should be: D first, then C, then B, then A
    graph = Taski::StaticAnalysis::DependencyGraph.new.build_from_cached(CleanTaskD)
    scheduler = Taski::Execution::Scheduler.new
    scheduler.load_graph(graph, CleanTaskD)
    scheduler.build_reverse_dependency_graph

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
    graph = Taski::StaticAnalysis::DependencyGraph.new.build_from_cached(FixtureTaskB)
    scheduler = Taski::Execution::Scheduler.new
    scheduler.load_graph(graph, FixtureTaskB)
    scheduler.build_reverse_dependency_graph

    ready = scheduler.next_ready_clean_tasks
    assert_includes ready, FixtureTaskB
    refute_includes ready, FixtureTaskA
  end

  def test_mark_clean_running_prevents_re_selection
    graph = Taski::StaticAnalysis::DependencyGraph.new.build_from_cached(FixtureTaskA)
    scheduler = Taski::Execution::Scheduler.new
    scheduler.load_graph(graph, FixtureTaskA)
    scheduler.build_reverse_dependency_graph

    ready1 = scheduler.next_ready_clean_tasks
    assert_includes ready1, FixtureTaskA

    scheduler.mark_clean_running(FixtureTaskA)

    ready2 = scheduler.next_ready_clean_tasks
    refute_includes ready2, FixtureTaskA
  end

  def test_mark_clean_completed
    graph = Taski::StaticAnalysis::DependencyGraph.new.build_from_cached(FixtureTaskA)
    scheduler = Taski::Execution::Scheduler.new
    scheduler.load_graph(graph, FixtureTaskA)
    scheduler.build_reverse_dependency_graph

    scheduler.mark_clean_running(FixtureTaskA)
    scheduler.mark_clean_completed(FixtureTaskA)

    assert scheduler.clean_completed?(FixtureTaskA)
  end

  def test_clean_order_is_reverse_of_run_order
    # FixtureTaskB -> FixtureTaskA
    # Run order: A first, then B
    # Clean order: B first, then A
    graph = Taski::StaticAnalysis::DependencyGraph.new.build_from_cached(FixtureTaskB)
    scheduler = Taski::Execution::Scheduler.new
    scheduler.load_graph(graph, FixtureTaskB)
    scheduler.build_reverse_dependency_graph

    # Step 1: Only B is ready to clean (no tasks depend on B)
    ready = scheduler.next_ready_clean_tasks
    assert_equal 1, ready.size
    assert_includes ready, FixtureTaskB

    # Step 2: Complete B's clean, now A becomes ready
    scheduler.mark_clean_running(FixtureTaskB)
    scheduler.mark_clean_completed(FixtureTaskB)

    ready = scheduler.next_ready_clean_tasks
    assert_includes ready, FixtureTaskA
  end

  def test_running_clean_tasks_returns_true_when_clean_tasks_running
    graph = Taski::StaticAnalysis::DependencyGraph.new.build_from_cached(FixtureTaskA)
    scheduler = Taski::Execution::Scheduler.new
    scheduler.load_graph(graph, FixtureTaskA)
    scheduler.build_reverse_dependency_graph

    refute scheduler.running_clean_tasks?

    scheduler.mark_clean_running(FixtureTaskA)
    assert scheduler.running_clean_tasks?

    scheduler.mark_clean_completed(FixtureTaskA)
    refute scheduler.running_clean_tasks?
  end

  def test_parallel_clean_for_independent_tasks
    # ParallelTaskC -> [ParallelTaskA, ParallelTaskB]
    # A and B are independent, so they can clean in parallel after C
    graph = Taski::StaticAnalysis::DependencyGraph.new.build_from_cached(ParallelTaskC)
    scheduler = Taski::Execution::Scheduler.new
    scheduler.load_graph(graph, ParallelTaskC)
    scheduler.build_reverse_dependency_graph

    # Step 1: Only C is ready (depends on A and B, but nothing depends on C)
    ready = scheduler.next_ready_clean_tasks
    assert_equal 1, ready.size
    assert_includes ready, ParallelTaskC

    # Step 2: Complete C, A and B become ready in parallel
    scheduler.mark_clean_running(ParallelTaskC)
    scheduler.mark_clean_completed(ParallelTaskC)

    ready = scheduler.next_ready_clean_tasks
    assert_equal 2, ready.size
    assert_includes ready, ParallelTaskA
    assert_includes ready, ParallelTaskB
  end

  def test_long_chain_clean_order
    # CleanTaskD -> CleanTaskC -> CleanTaskB -> CleanTaskA
    # Clean order: D, C, B, A
    graph = Taski::StaticAnalysis::DependencyGraph.new.build_from_cached(CleanTaskD)
    scheduler = Taski::Execution::Scheduler.new
    scheduler.load_graph(graph, CleanTaskD)
    scheduler.build_reverse_dependency_graph

    # Step 1: D is ready
    ready = scheduler.next_ready_clean_tasks
    assert_equal [CleanTaskD], ready

    # Step 2: Complete D, C becomes ready
    scheduler.mark_clean_running(CleanTaskD)
    scheduler.mark_clean_completed(CleanTaskD)
    ready = scheduler.next_ready_clean_tasks
    assert_equal [CleanTaskC], ready

    # Step 3: Complete C, B becomes ready
    scheduler.mark_clean_running(CleanTaskC)
    scheduler.mark_clean_completed(CleanTaskC)
    ready = scheduler.next_ready_clean_tasks
    assert_equal [CleanTaskB], ready

    # Step 4: Complete B, A becomes ready
    scheduler.mark_clean_running(CleanTaskB)
    scheduler.mark_clean_completed(CleanTaskB)
    ready = scheduler.next_ready_clean_tasks
    assert_equal [CleanTaskA], ready

    # Step 5: Complete A, no more tasks
    scheduler.mark_clean_running(CleanTaskA)
    scheduler.mark_clean_completed(CleanTaskA)
    ready = scheduler.next_ready_clean_tasks
    assert_equal [], ready
  end

  # ========================================
  # Skipped Task Classes Tests
  # ========================================

  def test_never_started_task_classes_returns_pending_tasks_after_execution
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

    graph = Taski::StaticAnalysis::DependencyGraph.new.build_from_cached(task_c)
    scheduler = Taski::Execution::Scheduler.new
    scheduler.load_graph(graph, task_c)

    # Only complete task_a
    scheduler.mark_running(task_a)
    scheduler.mark_completed(task_a)

    skipped = scheduler.never_started_task_classes
    assert_includes skipped, task_b
    assert_includes skipped, task_c
    refute_includes skipped, task_a
    assert_equal 2, skipped.size
  end

  def test_never_started_task_classes_returns_empty_when_all_completed
    task = Class.new(Taski::Task) do
      exports :value
      def run = @value = "test"
    end

    graph = Taski::StaticAnalysis::DependencyGraph.new.build_from_cached(task)
    scheduler = Taski::Execution::Scheduler.new
    scheduler.load_graph(graph, task)

    scheduler.mark_running(task)
    scheduler.mark_completed(task)

    assert_empty scheduler.never_started_task_classes
  end

  # ========================================
  # mark_skipped Tests
  # ========================================

  def test_mark_skipped_transitions_pending_to_skipped
    task = Class.new(Taski::Task) do
      exports :value
      def run = @value = "test"
    end

    graph = Taski::StaticAnalysis::DependencyGraph.new.build_from_cached(task)
    scheduler = Taski::Execution::Scheduler.new
    scheduler.load_graph(graph, task)

    assert scheduler.mark_skipped(task)
    assert_equal 1, scheduler.skipped_count
    # No longer pending
    refute_includes scheduler.never_started_task_classes, task
    # Not ready for execution
    assert_empty scheduler.next_ready_tasks
  end

  def test_mark_skipped_returns_false_from_running
    task = Class.new(Taski::Task) do
      exports :value
      def run = @value = "test"
    end

    graph = Taski::StaticAnalysis::DependencyGraph.new.build_from_cached(task)
    scheduler = Taski::Execution::Scheduler.new
    scheduler.load_graph(graph, task)

    scheduler.mark_running(task)
    refute scheduler.mark_skipped(task)
  end

  # ========================================
  # pending_dependents_of Tests
  # ========================================

  def test_pending_dependents_of_finds_direct_dependents
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

    graph = Taski::StaticAnalysis::DependencyGraph.new.build_from_cached(task_b)
    scheduler = Taski::Execution::Scheduler.new
    scheduler.load_graph(graph, task_b)

    # task_b depends on task_a, so task_b is a pending dependent of task_a
    dependents = scheduler.pending_dependents_of(task_a)
    assert_includes dependents, task_b
    refute_includes dependents, task_a
  end

  def test_pending_dependents_of_finds_transitive_dependents
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

    task_c = Class.new(Taski::Task) do
      exports :value
      def run = @value = "c"
    end
    task_c.define_singleton_method(:cached_dependencies) { Set[task_b] }

    graph = Taski::StaticAnalysis::DependencyGraph.new.build_from_cached(task_c)
    scheduler = Taski::Execution::Scheduler.new
    scheduler.load_graph(graph, task_c)

    # C -> B -> A. A fails -> B and C are pending dependents
    dependents = scheduler.pending_dependents_of(task_a)
    assert_includes dependents, task_b
    assert_includes dependents, task_c
  end

  def test_pending_dependents_of_excludes_running_tasks
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

    task_c = Class.new(Taski::Task) do
      exports :value
      def run = @value = "c"
    end
    task_c.define_singleton_method(:cached_dependencies) { Set[task_b] }

    graph = Taski::StaticAnalysis::DependencyGraph.new.build_from_cached(task_c)
    scheduler = Taski::Execution::Scheduler.new
    scheduler.load_graph(graph, task_c)

    # Mark B as running - it should not appear in pending dependents
    scheduler.mark_running(task_b)

    dependents = scheduler.pending_dependents_of(task_a)
    refute_includes dependents, task_b
    # C is still pending and transitively depends on A (through B)
    assert_includes dependents, task_c
  end

  def test_skipped_count
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

    graph = Taski::StaticAnalysis::DependencyGraph.new.build_from_cached(task_b)
    scheduler = Taski::Execution::Scheduler.new
    scheduler.load_graph(graph, task_b)

    assert_equal 0, scheduler.skipped_count

    scheduler.mark_skipped(task_b)
    assert_equal 1, scheduler.skipped_count
  end

  # ========================================
  # Unified State Model
  # ========================================

  def test_state_constants_are_unified_symbols
    # Run and clean phases share the same state values
    assert_equal :pending, Taski::Execution::Scheduler::STATE_PENDING
    assert_equal :running, Taski::Execution::Scheduler::STATE_RUNNING
    assert_equal :completed, Taski::Execution::Scheduler::STATE_COMPLETED
    assert_equal :skipped, Taski::Execution::Scheduler::STATE_SKIPPED
  end

  def test_no_enqueued_state_exists
    scheduler_constants = Taski::Execution::Scheduler.constants
    refute_includes scheduler_constants, :STATE_ENQUEUED,
      "enqueued state should not exist in unified model"
  end

  def test_run_phase_pending_to_running_to_completed
    task = Class.new(Taski::Task) do
      exports :value
      def run = @value = "test"
    end

    graph = Taski::StaticAnalysis::DependencyGraph.new.build_from_cached(task)
    scheduler = Taski::Execution::Scheduler.new
    scheduler.load_graph(graph, task)

    # pending
    assert_includes scheduler.next_ready_tasks, task
    refute scheduler.completed?(task)

    # running
    scheduler.mark_running(task)
    refute_includes scheduler.next_ready_tasks, task
    assert scheduler.running_tasks?

    # completed
    scheduler.mark_completed(task)
    assert scheduler.completed?(task)
    refute scheduler.running_tasks?
  end

  def test_run_phase_pending_to_running_to_failed
    task = Class.new(Taski::Task) do
      exports :value
      def run = raise "fail"
    end

    graph = Taski::StaticAnalysis::DependencyGraph.new.build_from_cached(task)
    scheduler = Taski::Execution::Scheduler.new
    scheduler.load_graph(graph, task)

    scheduler.mark_running(task)
    scheduler.mark_failed(task)

    # mark_failed should mark as failed AND count as completed for dependency ordering
    assert scheduler.completed?(task)
    refute scheduler.running_tasks?
  end

  def test_run_phase_pending_to_skipped
    task = Class.new(Taski::Task) do
      exports :value
      def run = @value = "test"
    end

    graph = Taski::StaticAnalysis::DependencyGraph.new.build_from_cached(task)
    scheduler = Taski::Execution::Scheduler.new
    scheduler.load_graph(graph, task)

    assert scheduler.mark_skipped(task)
    assert_equal 1, scheduler.skipped_count
    assert_empty scheduler.next_ready_tasks
  end

  def test_skipped_is_terminal_cannot_transition_to_running
    task = Class.new(Taski::Task) do
      exports :value
      def run = @value = "test"
    end

    graph = Taski::StaticAnalysis::DependencyGraph.new.build_from_cached(task)
    scheduler = Taski::Execution::Scheduler.new
    scheduler.load_graph(graph, task)

    scheduler.mark_skipped(task)

    # mark_running overwrites state but skipped task won't be in next_ready_tasks
    # and mark_skipped won't transition again
    refute scheduler.mark_skipped(task), "cannot skip an already-skipped task"
    refute_includes scheduler.next_ready_tasks, task, "skipped task should not appear as ready"
  end

  def test_clean_phase_pending_to_running_to_completed
    task = Class.new(Taski::Task) do
      exports :value
      def run = @value = "test"
    end

    graph = Taski::StaticAnalysis::DependencyGraph.new.build_from_cached(task)
    scheduler = Taski::Execution::Scheduler.new
    scheduler.load_graph(graph, task)
    scheduler.build_reverse_dependency_graph

    # pending
    assert_includes scheduler.next_ready_clean_tasks, task

    # running
    scheduler.mark_clean_running(task)
    refute_includes scheduler.next_ready_clean_tasks, task
    assert scheduler.running_clean_tasks?

    # completed
    scheduler.mark_clean_completed(task)
    assert scheduler.clean_completed?(task)
    refute scheduler.running_clean_tasks?
  end

  def test_clean_phase_pending_to_running_to_failed_tracks_failure_in_scheduler
    # mark_clean_failed sets state to STATE_FAILED but still adds to
    # @clean_finished_tasks so dependents are not blocked.
    task = Class.new(Taski::Task) do
      exports :value
      def run = @value = "test"
    end

    graph = Taski::StaticAnalysis::DependencyGraph.new.build_from_cached(task)
    scheduler = Taski::Execution::Scheduler.new
    scheduler.load_graph(graph, task)
    scheduler.build_reverse_dependency_graph

    scheduler.mark_clean_running(task)
    assert scheduler.running_clean_tasks?

    # mark_clean_failed adds to finished tasks (unblocks dependents) but records failure state
    scheduler.mark_clean_failed(task)
    assert scheduler.clean_completed?(task)
    refute scheduler.running_clean_tasks?
  end

  def test_clean_phase_uses_same_state_values_as_run
    # Both phases use STATE_PENDING, STATE_RUNNING, STATE_COMPLETED
    # No separate clean-specific state constants
    assert_equal Taski::Execution::Scheduler::STATE_PENDING, :pending
    assert_equal Taski::Execution::Scheduler::STATE_RUNNING, :running
    assert_equal Taski::Execution::Scheduler::STATE_COMPLETED, :completed
  end

  def test_pending_returns_true_for_pending_task
    task = Class.new(Taski::Task) do
      exports :value
      def run = @value = "test"
    end

    graph = Taski::StaticAnalysis::DependencyGraph.new.build_from_cached(task)
    scheduler = Taski::Execution::Scheduler.new
    scheduler.load_graph(graph, task)

    assert scheduler.pending?(task)
  end

  def test_pending_returns_false_for_running_task
    task = Class.new(Taski::Task) do
      exports :value
      def run = @value = "test"
    end

    graph = Taski::StaticAnalysis::DependencyGraph.new.build_from_cached(task)
    scheduler = Taski::Execution::Scheduler.new
    scheduler.load_graph(graph, task)

    scheduler.mark_running(task)
    refute scheduler.pending?(task)
  end

  def test_never_started_task_classes_does_not_include_running_tasks
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

    graph = Taski::StaticAnalysis::DependencyGraph.new.build_from_cached(task_b)
    scheduler = Taski::Execution::Scheduler.new
    scheduler.load_graph(graph, task_b)

    scheduler.mark_running(task_a)

    skipped = scheduler.never_started_task_classes
    # task_a is running (not pending), task_b is pending
    refute_includes skipped, task_a
    assert_includes skipped, task_b
  end
end
