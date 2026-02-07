# frozen_string_literal: true

require "test_helper"

class TestParallelExecution < Minitest::Test
  def setup
    # Reset the task system before each test
    Taski::Task.reset! if defined?(Taski::Task)
  end

  def test_basic_task_execution
    task_class = Class.new(Taski::Task) do
      exports :value

      def run
        @value = "exported_value"
        "run_return_value"
      end
    end

    # Test run's return value
    result = task_class.run
    assert_equal "run_return_value", result
  end

  def test_task_with_exported_method_override
    task_class = Class.new(Taski::Task) do
      exports :value

      def run
        value
      end

      def value
        "test_value"
      end
    end

    result = task_class.run
    assert_equal "test_value", result
  end

  def test_class_method_always_fresh_execution
    task_class = Class.new(Taski::Task) do
      exports :value

      def run
        @value = "value_#{rand(10000)}"
      end
    end

    # Class method calls should be fresh each time (no caching)
    value1 = task_class.value
    value2 = task_class.value

    refute_equal value1, value2, "Class method calls should execute fresh each time"
  end

  def test_reset_clears_cached_values
    unless Object.const_defined?(:ResetTaskTest)
      Object.const_set(:ResetTaskTest, Class.new(Taski::Task) do
        exports :value

        def run
          @value = rand(10000)
        end
      end)
    end

    value1 = ResetTaskTest.value
    ResetTaskTest.reset!
    value2 = ResetTaskTest.value

    assert value1 != value2, "Values should be different after reset"
  ensure
    Object.send(:remove_const, :ResetTaskTest) if Object.const_defined?(:ResetTaskTest)
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
    # Test default clean (no-op) doesn't break with run_and_clean
    task_class = Class.new(Taski::Task) do
      exports :value

      def run
        @value = "test"
      end
      # No clean method defined - should use default no-op
    end

    result = task_class.run_and_clean # Should not raise
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

  # Test Registry#get_task raises error for unregistered task
  def test_registry_get_task_raises_for_unregistered
    registry = Taski::Execution::Registry.new

    unregistered_class = Class.new(Taski::Task) do
      exports :value

      def run
        @value = "test"
      end
    end

    error = assert_raises(RuntimeError) do
      registry.get_task(unregistered_class)
    end
    assert_match(/not registered/, error.message)
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
    wrapper = Taski::Execution::TaskWrapper.new(task_instance, registry: registry)

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
    wrapper = Taski::Execution::TaskWrapper.new(task_instance, registry: registry)

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
    wrapper = Taski::Execution::TaskWrapper.new(task_instance, registry: registry)

    # Should raise NoMethodError for unknown method
    assert_raises(NoMethodError) do
      wrapper.completely_unknown_method
    end
  end

  # Test non-TaskAbortException error handling in Executor
  def test_executor_handles_non_abort_exception
    task_class = Class.new(Taski::Task) do
      exports :value

      def run
        raise StandardError, "Test error"
      end
    end

    error = assert_raises(Taski::AggregateError) do
      task_class.run
    end
    assert_equal 1, error.errors.size
    assert_equal "Test error", error.errors.first.error.message
  end

  # Test that wrapper timing is recorded
  def test_task_wrapper_timing
    task_class = Class.new(Taski::Task) do
      exports :value

      def run
        sleep 0.01
        @value = "test"
      end
    end

    registry = Taski::Execution::Registry.new
    task_instance = task_class.allocate
    task_instance.send(:initialize)
    wrapper = Taski::Execution::TaskWrapper.new(task_instance, registry: registry)

    # No timing before execution
    assert_nil wrapper.timing

    wrapper.mark_running
    refute_nil wrapper.timing
    assert_nil wrapper.timing.end_time

    result = task_instance.run
    wrapper.mark_completed(result)

    refute_nil wrapper.timing.end_time
    assert wrapper.timing.duration_ms >= 0
  end

  # Test that mark_failed records error
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
    wrapper = Taski::Execution::TaskWrapper.new(task_instance, registry: registry)

    wrapper.mark_running
    test_error = StandardError.new("Test error")
    wrapper.mark_failed(test_error)

    assert wrapper.completed?
    assert_equal test_error, wrapper.error
  end

  # ========================================
  # run_and_clean Integration Tests
  # ========================================

  def test_run_and_clean_basic_execution
    run_order = []
    clean_order = []

    task_class = Class.new(Taski::Task) do
      exports :value

      define_method(:run) do
        run_order << :task
        @value = "test_value"
      end

      define_method(:clean) do
        clean_order << :task
      end
    end

    result = task_class.run_and_clean
    assert_equal "test_value", result
    assert_equal [:task], run_order
    assert_equal [:task], clean_order
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

  def test_run_and_clean_error_still_cleans
    run_executed = false
    clean_executed = false

    task_class = Class.new(Taski::Task) do
      exports :value

      define_method(:run) do
        run_executed = true
        raise StandardError, "Run failed"
      end

      define_method(:clean) do
        clean_executed = true
      end
    end

    error = assert_raises(Taski::AggregateError) do
      task_class.run_and_clean
    end

    assert_equal 1, error.errors.size
    assert_equal "Run failed", error.errors.first.error.message
    assert run_executed, "Run should have been executed"
    assert clean_executed, "Clean should still execute after run failure"
  end

  def test_run_and_clean_returns_result
    task_class = Class.new(Taski::Task) do
      exports :computed

      def run
        @computed = 42 * 2
      end

      def clean
        # Cleanup logic
      end
    end

    result = task_class.run_and_clean
    assert_equal 84, result
  end

  # ========================================
  # run_and_clean with block Tests
  # ========================================

  def test_run_and_clean_with_block
    execution_order = []

    task_class = Class.new(Taski::Task) do
      exports :value

      define_method(:run) do
        execution_order << :run
        @value = "test_value"
      end

      define_method(:clean) do
        execution_order << :clean
      end
    end

    task_class.run_and_clean do
      execution_order << :block
    end

    assert_equal [:run, :block, :clean], execution_order
  end

  def test_run_and_clean_block_can_access_exported_values
    task_class = Class.new(Taski::Task) do
      exports :value

      def run
        @value = "exported_data"
      end

      def clean
      end
    end

    captured_value = nil
    task_class.run_and_clean do
      captured_value = task_class.value
    end

    assert_equal "exported_data", captured_value
  end

  def test_run_and_clean_block_can_use_stdout
    task_class = Class.new(Taski::Task) do
      exports :value

      def run
        @value = "test"
      end

      def clean
      end
    end

    # Verify block can write to stdout (capture is released)
    output = StringIO.new
    original_stdout = $stdout
    $stdout = output

    task_class.run_and_clean do
      puts "block output"
    end

    $stdout = original_stdout
    assert_includes output.string, "block output"
  end

  def test_run_and_clean_block_error_still_cleans
    clean_executed = false

    task_class = Class.new(Taski::Task) do
      exports :value

      define_method(:run) do
        @value = "test"
      end

      define_method(:clean) do
        clean_executed = true
      end
    end

    assert_raises(RuntimeError) do
      task_class.run_and_clean do
        raise "block error"
      end
    end

    assert clean_executed, "Clean should still execute after block raises"
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
