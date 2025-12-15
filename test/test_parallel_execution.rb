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
        @value = "test_value"
      end
    end

    result = task_class.run
    assert_equal "test_value", result
    assert_equal "test_value", task_class.value
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
    assert_equal "test_value", task_class.value
  end

  def test_task_caching
    task_class = Class.new(Taski::Task) do
      exports :value

      def run
        @value = "value_#{rand(10000)}"
      end
    end

    # First call
    value1 = task_class.value
    # Second call should return cached value
    value2 = task_class.value

    assert_equal value1, value2, "Values should be the same (cached)"
  end

  def test_new_creates_fresh_instance_for_re_execution
    task_class = Class.new(Taski::Task) do
      exports :value

      def run
        @value = "value_#{rand(10000)}"
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
        @value = "value_#{rand(10000)}"
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
          @ection_value = "Implementation 1"
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
    assert elapsed < 1.5, "Complex parallel execution should complete in < 1.5s, took #{elapsed}s"
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

    # Verify dependencies
    assert_equal ["ParallelChain1B", "ParallelChain2D"], ParallelChainFinal.cached_dependencies.map(&:name).sort
    assert_equal ["ParallelChain1A"], ParallelChain1B.cached_dependencies.map(&:name)
    assert_equal ["ParallelChain2C"], ParallelChain2D.cached_dependencies.map(&:name)

    # Execute
    start_time = Time.now
    result = ParallelChainFinal.run
    end_time = Time.now
    total_time = end_time - start_time

    # Verify result
    assert_includes result, "Chain1-B"
    assert_includes result, "Chain2-D"

    # Verify total execution time is close to 200ms (parallel) not 400ms (sequential)
    # Each chain is 200ms (100ms + 100ms), if parallel should be ~200ms total
    assert total_time < 0.35, "Parallel execution should take ~200ms, not 400ms. Took #{(total_time * 1000).round}ms"
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
    clean_result = CleanTaskD.clean

    # Wait for all clean threads to complete
    Taski::Task.registry.wait_all

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
end
