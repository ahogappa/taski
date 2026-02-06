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

    # Test exported value via instance (cached)
    task = task_class.new
    task.run
    assert_equal "exported_value", task.value
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
        @value = "value_#{rand(10_000)}"
      end
    end

    # Class method calls should be fresh each time (no caching)
    value1 = task_class.value
    value2 = task_class.value

    refute_equal value1, value2, "Class method calls should execute fresh each time"
  end

  def test_instance_caching
    task_class = Class.new(Taski::Task) do
      exports :value

      def run
        @value = "value_#{rand(10_000)}"
      end
    end

    # Instance should cache the value
    task = task_class.new
    value1 = task.value
    value2 = task.value

    assert_equal value1, value2, "Instance should cache the value"
  end

  def test_new_creates_fresh_instance_for_re_execution
    task_class = Class.new(Taski::Task) do
      exports :value

      def run
        @value = "value_#{rand(10_000)}"
      end
    end

    # TaskClass.new.run creates a fresh instance each time (re-execution)
    task1 = task_class.new
    result1 = task1.run
    task2 = task_class.new
    result2 = task2.run

    refute_equal result1, result2, "Each new instance should execute independently"
  end

  def test_new_instance_is_cached_within_itself
    task_class = Class.new(Taski::Task) do
      exports :value

      def run
        @value = "value_#{rand(10_000)}"
      end
    end

    # Same instance should be cached
    task = task_class.new
    result1 = task.run
    result2 = task.run

    assert_equal result1, result2, "Same instance should return cached value"
  end

  def test_new_returns_task_wrapper
    task_class = Class.new(Taski::Task) do
      exports :value

      def run
        @value = "test"
      end
    end

    instance = task_class.new
    assert_kind_of Taski::Execution::TaskWrapper, instance
  end

  def test_new_instance_can_access_exported_values
    task_class = Class.new(Taski::Task) do
      exports :value

      def run
        @value = "test_value"
      end
    end

    task = task_class.new
    task.run
    assert_equal "test_value", task.value
  end

  def test_section_implementation_selection
    # Define implementations
    unless Object.const_defined?(:SectionImplOne)
      Object.const_set(:SectionImplOne, Class.new(Taski::Task) do
        exports :section_value

        def run
          @section_value = "Implementation 1"
        end
      end)
    end

    unless Object.const_defined?(:SectionImplTwo)
      Object.const_set(:SectionImplTwo, Class.new(Taski::Task) do
        exports :section_value

        def run
          @section_value = "Implementation 2"
        end
      end)
    end

    # Define section
    unless Object.const_defined?(:TestSectionClass)
      Object.const_set(:TestSectionClass, Class.new(Taski::Section) do
        interfaces :section_value

        def impl
          SectionImplTwo
        end
      end)
    end

    result = TestSectionClass.section_value
    assert_equal "Implementation 2", result
  ensure
    # Clean up
    Object.send(:remove_const, :SectionImplOne) if Object.const_defined?(:SectionImplOne)
    Object.send(:remove_const, :SectionImplTwo) if Object.const_defined?(:SectionImplTwo)
    Object.send(:remove_const, :TestSectionClass) if Object.const_defined?(:TestSectionClass)
  end

  def test_reset_clears_cached_values
    unless Object.const_defined?(:ResetTaskTest)
      Object.const_set(:ResetTaskTest, Class.new(Taski::Task) do
        exports :value

        def run
          @value = rand(10_000)
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

  def test_section_with_dependencies
    require_relative "fixtures/parallel_tasks"

    Taski::Task.reset!

    # ParallelSection uses ParallelSectionImpl2 which has sleep
    result = ParallelSection.section_value

    assert_equal "Section Implementation 2", result
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
    assert_includes result, "Section Implementation"
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
    # TaskB has 0.5s sleep, ParallelSection has 0.3s sleep
    # If parallel, max should be around max(0.5, 0.3) + overhead
    # Sequential would be 0.5 + 0.3 = 0.8s+
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
    assert_equal %w[ParallelChain1B ParallelChain2D], ParallelChainFinal.cached_dependencies.map(&:name).sort
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
    assert start_time_diff < 0.05,
      "Independent chains should start nearly simultaneously. Difference: #{(start_time_diff * 1000).round}ms"
  end

  def test_clean_execution_order
    require_relative "fixtures/parallel_tasks"

    # Test that clean executes in reverse dependency order
    Taski::Task.reset!

    # First run to build the chain
    result = CleanTaskD.run
    assert_equal "D->C->B->A", result

    # Verify dependencies
    assert_equal ["CleanTaskC"], CleanTaskD.cached_dependencies.map(&:name)
    assert_equal ["CleanTaskB"], CleanTaskC.cached_dependencies.map(&:name)
    assert_equal ["CleanTaskA"], CleanTaskB.cached_dependencies.map(&:name)

    # Clean should execute D -> C -> B -> A (reverse of run)
    # Note: clean method is now synchronous and waits for completion
    clean_result = CleanTaskD.clean

    # Verify clean was called (values should be nil now)
    # Note: We can't directly verify execution order in the test without instrumentation
    # but we can verify clean was executed
    assert_equal "cleaned_D", clean_result
  end

  def test_clean_with_no_implementation
    # Test default clean (no-op) doesn't break
    task_class = Class.new(Taski::Task) do
      exports :value

      def run
        @value = "test"
      end
      # No clean method defined - should use default no-op
    end

    task_class.run
    result = task_class.clean # Should not raise, returns nil (default)
    assert_nil result
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

  # Test that Task.new instance reset! clears exported values and allows re-execution
  def test_task_instance_reset_clears_exported_values
    task_class = Class.new(Taski::Task) do
      exports :value

      def run
        @value = "value_#{rand(10_000)}"
      end
    end

    # Create instance and run
    task = task_class.new
    value1 = task.run
    assert_equal value1, task.value

    # Reset and run again - should get new value
    task.reset!
    value2 = task.run

    refute_equal value1, value2, "After reset!, re-execution should produce new value"
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

    # Failed tasks have state :failed, not :completed
    assert_equal :failed, wrapper.state
    refute wrapper.completed?, "Failed tasks should not be considered completed"
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
    assert_equal %i[base child], RunAndCleanFixtures::RunOrder.order

    # Clean should execute child first, then base (reverse dependency order)
    assert_equal %i[child base], RunAndCleanFixtures::CleanOrder.order
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
  # Pull API Integration Tests
  # ========================================

  def test_executor_sets_dependency_graph_on_context
    task_class = Class.new(Taski::Task) do
      exports :value

      def run
        @value = "test"
      end
    end

    registry = Taski::Execution::Registry.new
    context = Taski::Execution::ExecutionFacade.new

    Taski::Execution::Executor.execute(task_class, registry: registry, execution_context: context)

    # Verify dependency_graph is set and is the correct type
    refute_nil context.dependency_graph, "dependency_graph should be set after execution"
    assert_kind_of Taski::StaticAnalysis::DependencyGraph, context.dependency_graph

    # Verify graph contains at least the root task
    all_tasks = context.dependency_graph.all_tasks
    assert_includes all_tasks, task_class
  end
end
