# frozen_string_literal: true

require "test_helper"

class TestParallelExecution < Minitest::Test
  def setup
    # Reset the task system before each test
    Taski::Task.reset! if defined?(Taski::Task)
  end

  def test_basic_task_execution
    require_relative "fixtures/parallel_tasks"

    Taski::Task.reset!
    # Test run's return value
    result = BasicValueTask.run
    assert_equal "run_return_value", result
  end

  def test_task_with_exported_method_override
    require_relative "fixtures/parallel_tasks"

    Taski::Task.reset!
    result = ExportedMethodOverrideTask.run
    assert_equal "test_value", result
  end

  def test_class_method_always_fresh_execution
    require_relative "fixtures/parallel_tasks"

    Taski::Task.reset!
    # Class method calls should be fresh each time (no caching)
    value1 = FreshExecutionTask.value
    value2 = FreshExecutionTask.value

    refute_equal value1, value2, "Class method calls should execute fresh each time"
  end

  def test_reset_clears_cached_values
    require_relative "fixtures/parallel_tasks"

    Taski::Task.reset!
    value1 = FreshExecutionTask.value
    FreshExecutionTask.reset!
    value2 = FreshExecutionTask.value

    assert value1 != value2, "Values should be different after reset"
  end

  def test_parallel_execution_with_timing
    # Load fixtures
    require_relative "fixtures/parallel_tasks"

    Taski::Task.reset!

    # TaskC depends on TaskA (fast) and TaskB (0.5s sleep)
    # If execution is truly parallel, total time should be ~0.5s not 0.5s + TaskA time
    start_time = Time.now
    result = ParallelTaskC.task_c_value
    end_time = Time.now
    elapsed = end_time - start_time

    assert_includes result, "TaskA value"
    assert_includes result, "TaskB value"
    # Should complete in roughly 0.5s (TaskB's sleep time), not sequentially
    assert elapsed < 1.0, "Parallel execution should complete in < 1s, took #{elapsed}s"
  end

  def test_multiple_dependencies
    require_relative "fixtures/parallel_tasks"

    Taski::Task.reset!

    # TaskC depends on both TaskA and TaskB
    result = ParallelTaskC.task_c_value

    assert_includes result, "TaskA"
    assert_includes result, "TaskB"
  end

  def test_deep_dependency_chain
    require_relative "fixtures/parallel_tasks"

    Taski::Task.reset!

    # TaskH depends on TaskG, which depends on TaskE and TaskF
    # TaskE depends on TaskD, which depends on TaskC
    # TaskC depends on TaskA and TaskB
    result = DeepDependency::Nested::TaskH.task_h_value

    # Result should contain values from the entire dependency chain
    assert_includes result, "TaskH"
    assert_includes result, "TaskG"
    assert_includes result, "TaskE"
    assert_includes result, "TaskF"
  end

  def test_namespace_resolution
    require_relative "fixtures/parallel_tasks"

    Taski::Task.reset!

    # TaskF uses ::ParallelTaskA (absolute path reference)
    result = DeepDependency::TaskF.task_f_value

    assert_includes result, "TaskA value"
  end

  def test_complex_dependency_graph_with_timing
    require_relative "fixtures/parallel_tasks"

    Taski::Task.reset!

    # Deep dependency tree with multiple slow tasks
    # If parallel, should complete faster than sequential execution
    start_time = Time.now
    result = DeepDependency::Nested::TaskH.task_h_value
    end_time = Time.now
    elapsed = end_time - start_time

    assert_includes result, "TaskH"
    # TaskB has 0.5s sleep
    # If parallel, should complete in roughly max sleep time + overhead
    # Debug build (e.g. ruby 4.0.0dev) is slower, so allow more time
    time_limit = RUBY_DESCRIPTION.include?("dev") ? 3.0 : 1.5
    assert elapsed < time_limit, "Complex parallel execution should complete in < #{time_limit}s, took #{elapsed}s"
  end

  def test_sequential_execution_order_for_chain
    require_relative "fixtures/parallel_tasks"

    # Test that A->B->C->D chain executes in correct order
    Taski::Task.reset!

    # Verify dependencies
    assert_equal ["SequentialTaskC"], SequentialTaskD.cached_dependencies.map(&:name)
    assert_equal ["SequentialTaskB"], SequentialTaskC.cached_dependencies.map(&:name)
    assert_equal ["SequentialTaskA"], SequentialTaskB.cached_dependencies.map(&:name)
    assert_equal [], SequentialTaskA.cached_dependencies.map(&:name)

    # Execute the chain
    result = SequentialTaskD.run

    # Verify result contains the full chain
    assert_equal "D->C->B->A", result
  end

  def test_independent_chains_execute_in_parallel
    require_relative "fixtures/parallel_tasks"

    # Test that two independent chains execute in parallel
    # Chain 1: ParallelChain1A -> ParallelChain1B (200ms total)
    # Chain 2: ParallelChain2C -> ParallelChain2D (200ms total)
    # ParallelChainFinal depends on both chains
    Taski::Task.reset!
    ParallelChainStartTimes.reset

    # Verify dependencies
    assert_equal ["ParallelChain1B", "ParallelChain2D"], ParallelChainFinal.cached_dependencies.map(&:name).sort
    assert_equal ["ParallelChain1A"], ParallelChain1B.cached_dependencies.map(&:name)
    assert_equal ["ParallelChain2C"], ParallelChain2D.cached_dependencies.map(&:name)

    # Execute
    result = ParallelChainFinal.run

    # Verify result
    assert_includes result, "Chain1-B"
    assert_includes result, "Chain2-D"

    # Verify parallel execution by comparing start times of independent chains
    # If chains execute in parallel, both should start at approximately the same time
    chain1_start = ParallelChainStartTimes.get(:chain1a)
    chain2_start = ParallelChainStartTimes.get(:chain2c)

    refute_nil chain1_start, "Chain1A should have recorded start time"
    refute_nil chain2_start, "Chain2C should have recorded start time"

    # Start time difference should be minimal (< 50ms) if truly parallel
    # This is much more stable than checking total execution time
    start_time_diff = (chain1_start - chain2_start).abs
    assert start_time_diff < 0.05, "Independent chains should start nearly simultaneously. Difference: #{(start_time_diff * 1000).round}ms"
  end

  def test_clean_execution_order
    require_relative "fixtures/parallel_tasks"

    # Test that clean executes in reverse dependency order via run_and_clean
    Taski::Task.reset!

    # Verify dependencies
    assert_equal ["CleanTaskC"], CleanTaskD.cached_dependencies.map(&:name)
    assert_equal ["CleanTaskB"], CleanTaskC.cached_dependencies.map(&:name)
    assert_equal ["CleanTaskA"], CleanTaskB.cached_dependencies.map(&:name)

    # run_and_clean runs the task then cleans in reverse dependency order
    result = CleanTaskD.run_and_clean
    assert_equal "D->C->B->A", result
  end

  def test_clean_with_no_implementation
    require_relative "fixtures/parallel_tasks"

    Taski::Task.reset!
    # Test default clean (no-op) doesn't break with run_and_clean
    result = NoCleanTask.run_and_clean # Should not raise
    assert_equal "test", result
  end

  # Test that Task instance run raises NotImplementedError when not overridden
  def test_task_instance_run_raises_not_implemented_error
    task_class = Class.new(Taski::Task)
    # Directly instantiate and call run to test the error
    task_instance = task_class.allocate
    task_instance.send(:initialize)

    error = assert_raises(NotImplementedError) do
      task_instance.run
    end
    assert_match(/Subclasses must implement the run method/, error.message)
  end

  # Test Registry#registered? returns false for unregistered task
  def test_registry_registered_returns_false_for_unregistered
    registry = Taski::Execution::Registry.new

    unregistered_class = Class.new(Taski::Task) do
      exports :value

      def run
        @value = "test"
      end
    end

    refute registry.registered?(unregistered_class)
  end

  # Test TaskWrapper state methods
  def test_task_wrapper_state_methods
    task_class = Class.new(Taski::Task) do
      exports :value

      def run
        @value = "test"
      end
    end

    # Create a fresh registry and wrapper
    registry = Taski::Execution::Registry.new
    task_instance = task_class.allocate
    task_instance.send(:initialize)
    facade = Taski::Execution::ExecutionFacade.new(root_task_class: task_class)
    wrapper = Taski::Execution::TaskWrapper.new(task_instance, registry: registry, execution_facade: facade)

    # Initially pending
    assert_equal :pending, wrapper.state
    assert wrapper.pending?
    refute wrapper.completed?

    # After mark_running
    assert wrapper.mark_running

    # Cannot mark running twice
    refute wrapper.mark_running

    # After mark_completed
    wrapper.mark_completed("result")
    assert_equal :completed, wrapper.state
    refute wrapper.pending?
    assert wrapper.completed?
  end

  # Test TaskWrapper respond_to_missing? for unknown methods
  def test_task_wrapper_respond_to_missing_unknown_method
    task_class = Class.new(Taski::Task) do
      exports :value

      def run
        @value = "test"
      end
    end

    registry = Taski::Execution::Registry.new
    task_instance = task_class.allocate
    task_instance.send(:initialize)
    facade = Taski::Execution::ExecutionFacade.new(root_task_class: task_class)
    wrapper = Taski::Execution::TaskWrapper.new(task_instance, registry: registry, execution_facade: facade)

    # Should respond to exported method
    assert wrapper.respond_to?(:value)

    # Should not respond to unknown method
    refute wrapper.respond_to?(:unknown_method_that_does_not_exist)
  end

  # Test TaskWrapper method_missing for unknown methods
  def test_task_wrapper_method_missing_unknown_method
    task_class = Class.new(Taski::Task) do
      exports :value

      def run
        @value = "test"
      end
    end

    registry = Taski::Execution::Registry.new
    task_instance = task_class.allocate
    task_instance.send(:initialize)
    facade = Taski::Execution::ExecutionFacade.new(root_task_class: task_class)
    wrapper = Taski::Execution::TaskWrapper.new(task_instance, registry: registry, execution_facade: facade)

    # Should raise NoMethodError for unknown method
    assert_raises(NoMethodError) do
      wrapper.completely_unknown_method
    end
  end

  # Test non-TaskAbortException error handling in Executor
  def test_executor_handles_non_abort_exception
    require_relative "fixtures/parallel_tasks"

    Taski::Task.reset!
    error = assert_raises(Taski::AggregateError) do
      ErrorRaisingTask.run
    end
    assert_equal 1, error.errors.size
    assert_equal "Test error", error.errors.first.error.message
  end

  # Test that wrapper state transitions work correctly
  def test_task_wrapper_state_transitions
    task_class = Class.new(Taski::Task) do
      exports :value

      def run
        @value = "test"
      end
    end

    registry = Taski::Execution::Registry.new
    task_instance = task_class.allocate
    task_instance.send(:initialize)
    facade = Taski::Execution::ExecutionFacade.new(root_task_class: task_class)
    wrapper = Taski::Execution::TaskWrapper.new(task_instance, registry: registry, execution_facade: facade)

    # Starts as pending
    assert wrapper.pending?
    refute wrapper.completed?

    # mark_running transitions to running
    assert wrapper.mark_running
    refute wrapper.pending?
    refute wrapper.completed?

    # mark_completed transitions to completed
    result = task_instance.run
    wrapper.mark_completed(result)

    assert wrapper.completed?
    assert_equal "test", wrapper.result
  end

  # Test that mark_failed records error and sets STATE_FAILED
  def test_task_wrapper_mark_failed
    task_class = Class.new(Taski::Task) do
      exports :value

      def run
        @value = "test"
      end
    end

    registry = Taski::Execution::Registry.new
    task_instance = task_class.allocate
    task_instance.send(:initialize)
    facade = Taski::Execution::ExecutionFacade.new(root_task_class: task_class)
    wrapper = Taski::Execution::TaskWrapper.new(task_instance, registry: registry, execution_facade: facade)

    wrapper.mark_running
    test_error = StandardError.new("Test error")
    wrapper.mark_failed(test_error)

    assert wrapper.failed?
    refute wrapper.completed?
    assert_equal test_error, wrapper.error
  end

  # Test that wait_for_completion unblocks for failed tasks
  def test_task_wrapper_wait_for_completion_unblocks_on_failure
    task_class = Class.new(Taski::Task) do
      exports :value
      def run = @value = "test"
    end

    registry = Taski::Execution::Registry.new
    task_instance = task_class.allocate
    task_instance.send(:initialize)
    facade = Taski::Execution::ExecutionFacade.new(root_task_class: task_class)
    wrapper = Taski::Execution::TaskWrapper.new(task_instance, registry: registry, execution_facade: facade)

    wrapper.mark_running

    waiter = Thread.new { wrapper.wait_for_completion }
    sleep 0.05
    wrapper.mark_failed(StandardError.new("fail"))
    waiter.join(2)

    refute waiter.alive?, "wait_for_completion should unblock when task fails"
    assert wrapper.failed?
  end

  # ========================================
  # TaskWrapper mark_skipped Tests
  # ========================================

  def test_task_wrapper_mark_skipped
    task_class = Class.new(Taski::Task) do
      exports :value

      def run
        @value = "test"
      end
    end

    registry = Taski::Execution::Registry.new
    task_instance = task_class.allocate
    task_instance.send(:initialize)
    facade = Taski::Execution::ExecutionFacade.new(root_task_class: task_class)
    wrapper = Taski::Execution::TaskWrapper.new(task_instance, registry: registry, execution_facade: facade)

    # Initially pending
    assert wrapper.pending?

    # mark_skipped returns true on first call
    assert wrapper.mark_skipped

    # Now skipped
    assert wrapper.skipped?
    refute wrapper.completed?
    refute wrapper.pending?

    # mark_skipped returns false when already skipped
    refute wrapper.mark_skipped
  end

  def test_task_wrapper_mark_skipped_only_from_pending
    task_class = Class.new(Taski::Task) do
      exports :value

      def run
        @value = "test"
      end
    end

    registry = Taski::Execution::Registry.new
    task_instance = task_class.allocate
    task_instance.send(:initialize)
    facade = Taski::Execution::ExecutionFacade.new(root_task_class: task_class)
    wrapper = Taski::Execution::TaskWrapper.new(task_instance, registry: registry, execution_facade: facade)

    # Transition to running first
    assert wrapper.mark_running

    # Cannot skip from running state
    refute wrapper.mark_skipped
    refute wrapper.skipped?
  end

  # ========================================
  # run_and_clean Integration Tests
  # ========================================

  def test_run_and_clean_basic_execution
    require_relative "fixtures/run_and_clean_fixtures"
    RunAndCleanFixtures::BlockOrder.clear

    result = RunAndCleanFixtures::TrackedRunCleanTask.run_and_clean
    assert_equal "test_value", result
    assert_includes RunAndCleanFixtures::BlockOrder.order, :run
    assert_includes RunAndCleanFixtures::BlockOrder.order, :clean
  end

  def test_run_and_clean_with_dependencies
    # Use fixtures for proper static analysis dependency detection
    # We'll verify order using simple counters within fixture classes
    require_relative "fixtures/run_and_clean_fixtures"

    # Clear any previous state
    RunAndCleanFixtures::RunOrder.clear
    RunAndCleanFixtures::CleanOrder.clear

    result = RunAndCleanFixtures::ChildTask.run_and_clean
    assert_equal "base_child", result

    # Run should execute base first, then child (dependency order)
    assert_equal [:base, :child], RunAndCleanFixtures::RunOrder.order

    # Clean should execute child first, then base (reverse dependency order)
    assert_equal [:child, :base], RunAndCleanFixtures::CleanOrder.order
  end

  def test_run_and_clean_default_skips_clean_on_run_failure
    require_relative "fixtures/run_and_clean_fixtures"
    RunAndCleanFixtures::CleanOnFailureTracker.clear

    error = assert_raises(Taski::AggregateError) do
      RunAndCleanFixtures::FailingCleanableTask.run_and_clean
    end

    assert_equal 1, error.errors.size
    assert_equal "Run failed", error.errors.first.error.message
    assert RunAndCleanFixtures::CleanOnFailureTracker.run_executed?, "Run should have been executed"
    refute RunAndCleanFixtures::CleanOnFailureTracker.clean_executed?, "Clean should NOT execute after run failure by default"
  end

  def test_run_and_clean_with_clean_on_failure_runs_clean
    require_relative "fixtures/run_and_clean_fixtures"
    RunAndCleanFixtures::CleanOnFailureTracker.clear

    error = assert_raises(Taski::AggregateError) do
      RunAndCleanFixtures::FailingCleanableTask.run_and_clean(clean_on_failure: true)
    end

    assert_equal 1, error.errors.size
    assert_equal "Run failed", error.errors.first.error.message
    assert RunAndCleanFixtures::CleanOnFailureTracker.run_executed?, "Run should have been executed"
    assert RunAndCleanFixtures::CleanOnFailureTracker.clean_executed?, "Clean should execute after run failure with clean_on_failure: true"
  end

  def test_run_and_clean_success_always_cleans_regardless_of_option
    require_relative "fixtures/run_and_clean_fixtures"
    RunAndCleanFixtures::CleanOnFailureTracker.clear

    RunAndCleanFixtures::SucceedingCleanableTask.run_and_clean
    assert RunAndCleanFixtures::CleanOnFailureTracker.clean_executed?, "Clean should execute when run succeeds"
  end

  def test_run_and_clean_returns_result
    require_relative "fixtures/run_and_clean_fixtures"

    result = RunAndCleanFixtures::ComputedResultTask.run_and_clean
    assert_equal 84, result
  end

  # ========================================
  # run_and_clean with block Tests
  # ========================================

  def test_run_and_clean_with_block
    require_relative "fixtures/run_and_clean_fixtures"
    RunAndCleanFixtures::BlockOrder.clear

    RunAndCleanFixtures::TrackedBlockTask.run_and_clean do
      RunAndCleanFixtures::BlockOrder.add(:block)
    end

    assert_equal [:run, :block, :clean], RunAndCleanFixtures::BlockOrder.order
  end

  def test_run_and_clean_block_can_access_exported_values
    require_relative "fixtures/run_and_clean_fixtures"

    captured_value = nil
    RunAndCleanFixtures::ExportedDataTask.run_and_clean do
      captured_value = RunAndCleanFixtures::ExportedDataTask.value
    end

    assert_equal "exported_data", captured_value
  end

  def test_run_and_clean_block_can_use_stdout
    require_relative "fixtures/run_and_clean_fixtures"

    # Verify block can write to stdout (capture is released)
    output = StringIO.new
    original_stdout = $stdout
    begin
      $stdout = output

      RunAndCleanFixtures::StdoutTestTask.run_and_clean do
        puts "block output"
      end
    ensure
      $stdout = original_stdout
    end

    assert_includes output.string, "block output"
  end

  def test_run_and_clean_block_error_still_cleans
    require_relative "fixtures/run_and_clean_fixtures"
    RunAndCleanFixtures::BlockErrorTracker.clear

    assert_raises(RuntimeError) do
      RunAndCleanFixtures::CleanOnBlockErrorTask.run_and_clean do
        raise "block error"
      end
    end

    assert RunAndCleanFixtures::BlockErrorTracker.clean_executed?, "Clean should still execute after block raises"
  end

  # ========================================
  # API Removal Tests
  # ========================================

  def test_task_clean_is_not_public
    task_class = Class.new(Taski::Task) do
      exports :value
      def run
        @value = "test"
      end
    end

    refute task_class.respond_to?(:clean), "Task.clean should not be a public class method"
  end

  def test_task_new_is_not_public
    task_class = Class.new(Taski::Task) do
      exports :value
      def run
        @value = "test"
      end
    end

    refute task_class.respond_to?(:new), "Task.new should not be a public class method"
  end
end
