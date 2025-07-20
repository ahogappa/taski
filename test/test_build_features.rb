# frozen_string_literal: true

require_relative "test_helper"

class TestBuildFeatures < Minitest::Test
  include TaskiTestHelper

  def setup
    setup_taski_test
  end

  def teardown
    # Tasks created in tests are isolated and don't need cleanup
  end

  # ===================================================================
  # PARAMETRIZED BUILD TESTS
  # ===================================================================

  # Basic parametrized build functionality
  def test_build_without_args_returns_instance
    task_class = Class.new(Taski::Task) do
      def self.name
        "TestTask"
      end

      def run
        @result = "default"
      end
    end

    result = task_class.run
    assert_instance_of task_class, result
    assert_equal "default", result.instance_variable_get(:@result)
  end

  def test_build_with_args_returns_different_instance
    task_class = Class.new(Taski::Task) do
      def self.name
        "TestTask"
      end

      def run
        args = build_args
        @result = args[:mode] || "default"
      end
    end

    # Build without args - returns singleton instance
    singleton_instance = task_class.run
    assert_instance_of task_class, singleton_instance
    assert_equal "default", singleton_instance.instance_variable_get(:@result)

    # Build with args - returns different temporary instance
    temp_instance = task_class.run(mode: "fast")
    assert_instance_of task_class, temp_instance
    assert_equal "fast", temp_instance.instance_variable_get(:@result)

    # Should be different instances
    refute_equal singleton_instance, temp_instance
  end

  def test_build_args_accessible_in_instance_build
    task_class = Class.new(Taski::Task) do
      def self.name
        "TestTask"
      end

      def run
        args = build_args
        @mode = args[:mode]
        @input = args[:input]
        @result = "processed_#{@mode}_#{@input}"
      end
    end

    instance = task_class.run(mode: "thorough", input: "data")
    assert_equal "thorough", instance.instance_variable_get(:@mode)
    assert_equal "data", instance.instance_variable_get(:@input)
    assert_equal "processed_thorough_data", instance.instance_variable_get(:@result)
  end

  def test_build_args_empty_for_no_args_build
    task_class = Class.new(Taski::Task) do
      def self.name
        "TestTask"
      end

      def run
        @args_size = build_args.size
      end

      attr_reader :args_size
    end

    # Build without args - instance uses singleton pattern
    instance = task_class.run
    assert_equal 0, instance.args_size
  end

  # Dependencies with parametrized builds
  def test_dependencies_resolved_with_parametrized_build
    base_task = Class.new(Taski::Task) do
      exports :base_result

      def self.name
        "ParametrizedBaseTask"
      end

      def run
        @base_result = "base_built"
      end
    end
    Object.const_set(:ParametrizedBaseTask, base_task)

    dependent_task = Class.new(Taski::Task) do
      exports :dependent_result

      def self.name
        "ParametrizedDependentTask"
      end

      def run
        # Create natural dependency by accessing ParametrizedBaseTask
        ParametrizedBaseTask.base_result  # This creates the dependency
        args = build_args
        @dependent_result = "dependent_built_#{args[:option] || "default"}"
      end
    end
    Object.const_set(:ParametrizedDependentTask, dependent_task)

    instance = dependent_task.run(option: "value")

    # Base task should have been built through dependency resolution
    assert_equal "base_built", ParametrizedBaseTask.base_result
    assert_equal "dependent_built_value", instance.dependent_result
  end

  # Multiple parametrized builds don't interfere
  def test_multiple_parametrized_builds_independent
    task_class = Class.new(Taski::Task) do
      def self.name
        "TestTask"
      end

      def run
        args = build_args
        @result = "result_#{args[:id]}"
      end
    end

    instance1 = task_class.run(id: "first")
    instance2 = task_class.run(id: "second")

    assert_equal "result_first", instance1.instance_variable_get(:@result)
    assert_equal "result_second", instance2.instance_variable_get(:@result)
    refute_equal instance1, instance2
  end

  # Backward compatibility (return value changed but functionality preserved)
  def test_singleton_behavior_preserved
    task_class = Class.new(Taski::Task) do
      def self.name
        "TestTask"
      end

      def run
        @result = "original_behavior"
      end
    end

    # Build returns instance now instead of class
    result = task_class.run
    assert_instance_of task_class, result
    assert_equal "original_behavior", result.instance_variable_get(:@result)

    # Singleton instance should be created and same as returned instance
    singleton_instance = task_class.instance_variable_get(:@__task_instance)
    refute_nil singleton_instance
    assert_equal result, singleton_instance
    assert_equal "original_behavior", singleton_instance.instance_variable_get(:@result)
  end

  # Error handling
  def test_error_in_parametrized_build_includes_args
    task_class = Class.new(Taski::Task) do
      def self.name
        "FailingTask"
      end

      def run
        # Check if this is a parametrized build
        if build_args.any?
          raise StandardError, "parametrized build failed"
        else
          @result = "success"
        end
      end
    end

    # First ensure normal build works
    normal_instance = task_class.run
    assert_equal "success", normal_instance.instance_variable_get(:@result)

    # Now test parametrized build failure
    error = assert_raises(Taski::TaskBuildError) do
      task_class.run(mode: "test")
    end

    assert_includes error.message, "FailingTask"
    assert_includes error.message, '{mode: "test"}'
  end

  # ===================================================================
  # INTEGRATION TESTS
  # ===================================================================

  def test_simple_integration_workflow
    # Test a simple workflow with explicit dependencies

    # Base task
    base_task = Class.new(Taski::Task) do
      exports :config

      def run
        TaskiTestHelper.track_build_order("BaseTask")
        @config = "base-config"
      end
    end
    Object.const_set(:BaseTask, base_task)

    # Dependent task that naturally depends on BaseTask
    dependent_task = Class.new(Taski::Task) do
      exports :result

      def run
        TaskiTestHelper.track_build_order("DependentTask")
        @result = "result-using-#{BaseTask.config}"
      end
    end
    Object.const_set(:DependentTask, dependent_task)

    # Reset and build
    TaskiTestHelper.reset_build_order
    DependentTask.run

    # Verify build order
    build_order = TaskiTestHelper.build_order
    base_idx = build_order.index("BaseTask")
    dependent_idx = build_order.index("DependentTask")

    refute_nil base_idx, "BaseTask should be built"
    refute_nil dependent_idx, "DependentTask should be built"
    assert base_idx < dependent_idx, "BaseTask should be built before DependentTask"

    # Verify result
    assert_equal "result-using-base-config", DependentTask.result
  end

  def test_mixed_api_integration
    # Test mixing exports and define APIs

    # Define API task
    define_task = Class.new(Taski::Task) do
      define :shared_value, -> { "shared-data" }

      def run
        TaskiTestHelper.track_build_order("DefineTask")
        puts shared_value
      end
    end
    Object.const_set(:DefineTask, define_task)

    # Exports API task that depends on DefineTask
    exports_task = Class.new(Taski::Task) do
      exports :combined_result

      def run
        TaskiTestHelper.track_build_order("ExportsTask")
        @combined_result = "exports-#{DefineTask.shared_value}"
      end
    end
    Object.const_set(:ExportsTask, exports_task)

    # Reset and build
    TaskiTestHelper.reset_build_order
    capture_io { ExportsTask.run }

    # Verify build order
    build_order = TaskiTestHelper.build_order
    define_idx = build_order.index("DefineTask")
    exports_idx = build_order.index("ExportsTask")

    refute_nil define_idx, "DefineTask should be built"
    refute_nil exports_idx, "ExportsTask should be built"
    assert define_idx < exports_idx, "DefineTask should be built before ExportsTask"

    # Verify values
    assert_equal "shared-data", DefineTask.shared_value
    assert_equal "exports-shared-data", ExportsTask.combined_result
  end

  def test_reset_and_rebuild_integration
    # Test that reset and rebuild works correctly

    build_counter = 0
    task = Class.new(Taski::Task) do
      exports :timestamp, :build_number

      define_method :run do
        build_counter += 1
        @build_number = build_counter
        @timestamp = Time.now.to_f
      end
    end
    Object.const_set(:TimestampTask, task)

    # Build first time
    TimestampTask.run
    first_timestamp = TimestampTask.timestamp
    first_build_number = TimestampTask.build_number

    # Reset and build again
    TimestampTask.reset!
    TimestampTask.run
    second_timestamp = TimestampTask.timestamp
    second_build_number = TimestampTask.build_number

    # Should have different build numbers (more reliable than timestamps)
    assert_equal 1, first_build_number
    assert_equal 2, second_build_number

    # Timestamps should also be different (but this is less critical)
    refute_equal first_timestamp, second_timestamp
  end

  def test_error_handling_integration
    # Test error handling in integration scenario

    failing_task = Class.new(Taski::Task) do
      def run
        raise StandardError, "Integration test failure"
      end
    end
    Object.const_set(:FailingIntegrationTask, failing_task)

    dependent_task = Class.new(Taski::Task) do
      def run
        # This will create a natural dependency on FailingIntegrationTask
        # and should never execute because FailingIntegrationTask will fail first
        FailingIntegrationTask.run
        puts "This should not execute"
      end
    end
    Object.const_set(:DependentIntegrationTask, dependent_task)

    # Should raise TaskBuildError
    assert_raises(Taski::TaskBuildError) do
      DependentIntegrationTask.run
    end
  end

  def test_granular_task_execution
    # Test that individual tasks can be executed independently

    # Create a dependency chain: A -> B -> C
    task_a = Class.new(Taski::Task) do
      exports :value_a

      def run
        TaskiTestHelper.track_build_order("TaskA")
        @value_a = "A"
      end
    end
    Object.const_set(:GranularTaskA, task_a)

    task_b = Class.new(Taski::Task) do
      exports :value_b

      def run
        TaskiTestHelper.track_build_order("TaskB")
        @value_b = "B-#{GranularTaskA.value_a}"
      end
    end
    Object.const_set(:GranularTaskB, task_b)

    task_c = Class.new(Taski::Task) do
      exports :value_c

      def run
        TaskiTestHelper.track_build_order("TaskC")
        @value_c = "C-#{GranularTaskB.value_b}"
      end
    end
    Object.const_set(:GranularTaskC, task_c)

    # Test 1: Build only TaskA
    TaskiTestHelper.reset_build_order
    GranularTaskA.run

    assert_equal ["TaskA"], TaskiTestHelper.build_order
    assert_equal "A", GranularTaskA.value_a

    # Test 2: Build TaskB (should also build TaskA if not already built)
    GranularTaskA.reset!
    GranularTaskB.reset!
    TaskiTestHelper.reset_build_order
    GranularTaskB.run

    assert_equal ["TaskA", "TaskB"], TaskiTestHelper.build_order
    assert_equal "B-A", GranularTaskB.value_b

    # Test 3: Access value directly (should trigger build)
    GranularTaskA.reset!
    GranularTaskB.reset!
    GranularTaskC.reset!
    TaskiTestHelper.reset_build_order

    result = GranularTaskC.value_c
    assert_equal "C-B-A", result
    assert_equal ["TaskA", "TaskB", "TaskC"], TaskiTestHelper.build_order
  end

  def test_partial_dependency_graph_setup_and_verification
    # Test setting up a complex dependency graph for partial execution
    # Creates a diamond-shaped dependency structure:
    #     Config
    #    /      \
    # Database  Cache
    #    \      /
    #   Application

    setup_partial_dependency_graph

    # Verify tasks are properly defined
    assert PartialConfig.respond_to?(:build)
    assert PartialDatabase.respond_to?(:build)
    assert PartialCache.respond_to?(:build)
    assert PartialApplication.respond_to?(:build)
  end

  def test_partial_execution_database_branch
    # Test executing only the database branch of dependency graph
    # Should build Config -> Database, but not Cache

    setup_partial_dependency_graph

    # Reset all tasks to ensure clean state
    PartialConfig.reset!
    PartialDatabase.reset!

    TaskiTestHelper.reset_build_order
    PartialDatabase.run

    assert_equal ["Config", "Database"], TaskiTestHelper.build_order
    assert_equal "db-production", PartialDatabase.connection

    # Cache should not be built
    refute_includes TaskiTestHelper.build_order, "Cache"
  end

  def test_partial_execution_cache_branch
    # Test executing only the cache branch of dependency graph
    # Should build Config -> Cache, but not Database

    setup_partial_dependency_graph

    PartialConfig.reset!
    PartialCache.reset!
    TaskiTestHelper.reset_build_order
    PartialCache.run

    assert_equal ["Config", "Cache"], TaskiTestHelper.build_order
    assert_equal "cache-production", PartialCache.cache_url

    # Database should not be built
    refute_includes TaskiTestHelper.build_order, "Database"
  end

  # ===================================================================
  # PARAMETRIZED BUILD CACHE BEHAVIOR TESTS
  # ===================================================================

  def test_parametrized_cache_maintains_for_order_changes
    # Cache should be maintained when argument order changes but keys are same
    task_class = Class.new(Taski::Task) do
      exports :result

      def self.name
        "CacheOrderTask"
      end

      def run
        args = build_args
        @result = "args_#{args.inspect}"
      end
    end
    Object.const_set(:CacheOrderTask, task_class)

    # First call with specific order
    first_result = CacheOrderTask.run(a: 1, b: 2)
    first_object_id = first_result.object_id

    # Second call with different order but same keys
    second_result = CacheOrderTask.run(b: 2, a: 1)
    second_object_id = second_result.object_id

    # Should return same cached instance
    assert_equal first_object_id, second_object_id
    assert_equal first_result.result, second_result.result
  end

  def test_parametrized_cache_clears_for_key_additions
    # Cache should be cleared when argument keys are added
    task_class = Class.new(Taski::Task) do
      exports :result

      def self.name
        "CacheAdditionTask"
      end

      def run
        args = build_args
        @result = "args_#{args.inspect}"
      end
    end
    Object.const_set(:CacheAdditionTask, task_class)

    # First call with two keys
    first_result = CacheAdditionTask.run(a: 1, b: 2)
    first_object_id = first_result.object_id

    # Second call with additional key
    second_result = CacheAdditionTask.run(a: 1, b: 2, c: 3)
    second_object_id = second_result.object_id

    # Should create new instance (cache cleared)
    refute_equal first_object_id, second_object_id
    refute_equal first_result.result, second_result.result
  end

  def test_parametrized_cache_clears_for_key_removals
    # Cache should be cleared when argument keys are removed
    task_class = Class.new(Taski::Task) do
      exports :result

      def self.name
        "CacheRemovalTask"
      end

      def run
        args = build_args
        @result = "args_#{args.inspect}"
      end
    end
    Object.const_set(:CacheRemovalTask, task_class)

    # First call with three keys
    first_result = CacheRemovalTask.run(a: 1, b: 2, c: 3)
    first_object_id = first_result.object_id

    # Second call with one key removed
    second_result = CacheRemovalTask.run(a: 1, b: 2)
    second_object_id = second_result.object_id

    # Should create new instance (cache cleared)
    refute_equal first_object_id, second_object_id
    refute_equal first_result.result, second_result.result
  end

  def test_parametrized_cache_distinguishes_nil_values
    # Cache should distinguish between explicit nil and omitted values
    task_class = Class.new(Taski::Task) do
      exports :result

      def self.name
        "CacheNilTask"
      end

      def run
        args = build_args
        @result = "args_#{args.inspect}"
      end
    end
    Object.const_set(:CacheNilTask, task_class)

    # First call without nil values
    first_result = CacheNilTask.run(a: 1, b: 2)
    first_object_id = first_result.object_id

    # Second call with nil value added - should create new instance
    second_result = CacheNilTask.run(a: 1, b: 2, c: nil)
    second_object_id = second_result.object_id

    # Should return different instances (nil is significant)
    refute_equal first_object_id, second_object_id
    refute_equal first_result.result, second_result.result

    # But same arguments should use cache
    third_result = CacheNilTask.run(a: 1, b: 2, c: nil)
    assert_equal second_object_id, third_result.object_id
  end

  def test_parametrized_cache_single_cache_strategy
    # Only one cache should be maintained at a time (single cache strategy)
    task_class = Class.new(Taski::Task) do
      exports :result

      def self.name
        "SingleCacheTask"
      end

      def run
        args = build_args
        @result = "args_#{args.inspect}"
      end
    end
    Object.const_set(:SingleCacheTask, task_class)

    # First call with specific args
    first_result = SingleCacheTask.run(a: 1, b: 2)
    first_object_id = first_result.object_id

    # Second call with different args (should clear first cache)
    second_result = SingleCacheTask.run(x: 10, y: 20)
    second_object_id = second_result.object_id

    # Third call with original args (should not restore first cache)
    third_result = SingleCacheTask.run(a: 1, b: 2)
    third_object_id = third_result.object_id

    # First and third should be different instances (cache was cleared)
    refute_equal first_object_id, third_object_id
    # Second and third should be different (different args)
    refute_equal second_object_id, third_object_id
  end

  def test_parametrized_cache_maintains_after_order_change_then_same_keys
    # Test cache behavior with order changes and subsequent calls
    task_class = Class.new(Taski::Task) do
      exports :result

      def self.name
        "OrderMaintainTask"
      end

      def run
        args = build_args
        @result = "args_#{args.inspect}"
      end
    end
    Object.const_set(:OrderMaintainTask, task_class)

    # First call
    first_result = OrderMaintainTask.run(a: 1, b: 2, c: 3)
    first_object_id = first_result.object_id

    # Second call with different order (should use cache)
    second_result = OrderMaintainTask.run(c: 3, a: 1, b: 2)
    second_object_id = second_result.object_id
    assert_equal first_object_id, second_object_id

    # Third call with same keys as first call (should still use cache)
    third_result = OrderMaintainTask.run(a: 1, b: 2, c: 3)
    third_object_id = third_result.object_id
    assert_equal first_object_id, third_object_id
  end

  # ===================================================================
  # COMBINED PARAMETRIZED BUILD AND INTEGRATION TESTS
  # ===================================================================

  def test_parametrized_build_in_dependency_chain
    # Test parametrized builds working within complex dependency chains

    # Base task that accepts parameters
    base_task = Class.new(Taski::Task) do
      exports :config_value

      def self.name
        "ParametrizedConfigTask"
      end

      def run
        args = build_args
        mode = args[:mode] || "default"
        TaskiTestHelper.track_build_order("Config-#{mode}")
        @config_value = "config-#{mode}"
      end
    end
    Object.const_set(:ParametrizedConfigTask, base_task)

    # Middle task that depends on parametrized base task
    middle_task = Class.new(Taski::Task) do
      exports :processed_config

      def self.name
        "MiddleProcessorTask"
      end

      def run
        # This should trigger parametrized build of base task
        config = ParametrizedConfigTask.run(mode: "production").config_value
        TaskiTestHelper.track_build_order("Processor")
        @processed_config = "processed-#{config}"
      end
    end
    Object.const_set(:MiddleProcessorTask, middle_task)

    # Final task that depends on middle task
    final_task = Class.new(Taski::Task) do
      exports :final_result

      def run
        TaskiTestHelper.track_build_order("Final")
        @final_result = "final-#{MiddleProcessorTask.processed_config}"
      end
    end
    Object.const_set(:FinalResultTask, final_task)

    TaskiTestHelper.reset_build_order
    result = FinalResultTask.run

    # Verify build order includes parametrized build
    build_order = TaskiTestHelper.build_order
    assert_includes build_order, "Config-production"
    assert_includes build_order, "Processor"
    assert_includes build_order, "Final"

    # Verify correct processing of parametrized values
    assert_equal "final-processed-config-production", result.final_result
  end

  def test_parametrized_build_error_handling_in_integration
    # Test error handling when parametrized builds fail in dependency chains

    failing_param_task = Class.new(Taski::Task) do
      def self.name
        "FailingParametrizedTask"
      end

      def run
        args = build_args
        if args[:fail] == true
          raise StandardError, "Parametrized task intentionally failed"
        end
        @result = "success"
      end
    end
    Object.const_set(:FailingParametrizedTask, failing_param_task)

    dependent_task = Class.new(Taski::Task) do
      def run
        # This should trigger the failing parametrized build
        FailingParametrizedTask.run(fail: true)
      end
    end
    Object.const_set(:DependentOnFailingTask, dependent_task)

    # Should propagate TaskBuildError with parametrized build information
    error = assert_raises(Taski::TaskBuildError) do
      DependentOnFailingTask.run
    end

    assert_includes error.message, "FailingParametrizedTask"
    assert_includes error.message, "{fail: true}"
  end

  def test_reset_behavior_with_parametrized_builds
    # Test that reset! works correctly with parametrized builds

    counter = 0
    resettable_task = Class.new(Taski::Task) do
      exports :value

      def self.name
        "ResettableParametrizedTask"
      end

      define_method :run do
        counter += 1
        args = build_args
        mode = args[:mode] || "default"
        @value = "#{mode}-#{counter}"
      end
    end
    Object.const_set(:ResettableParametrizedTask, resettable_task)

    # First build without parameters (singleton)
    first_singleton = ResettableParametrizedTask.run
    assert_equal "default-1", first_singleton.value

    # Parametrized build (temporary instance)
    first_param = ResettableParametrizedTask.run(mode: "test")
    assert_equal "test-2", first_param.instance_variable_get(:@value)

    # Reset and build again
    ResettableParametrizedTask.reset!

    # Singleton should rebuild
    second_singleton = ResettableParametrizedTask.run
    assert_equal "default-3", second_singleton.value

    # Parametrized build should also work after reset
    second_param = ResettableParametrizedTask.run(mode: "test")
    assert_equal "test-4", second_param.instance_variable_get(:@value)

    # Verify instances are different but values are as expected
    refute_equal first_singleton, second_singleton
    refute_equal first_param, second_param
  end

  def test_mixed_parametrized_and_singleton_builds_in_chain
    # Test mixing parametrized and singleton builds in the same dependency chain

    setup_mixed_build_chain

    TaskiTestHelper.reset_build_order

    # Access the final result which should trigger the entire chain
    result = MixedChainFinal.final_value

    # Verify correct build order and parameter passing
    build_order = TaskiTestHelper.build_order
    assert_includes build_order, "Root"
    assert_includes build_order, "Param-fast"
    assert_includes build_order, "Final"

    assert_equal "final-param-fast-root", result
  end

  # ===================================================================
  # INSTANCE BUILDER TESTS
  # ===================================================================

  def test_instance_builder_can_be_created
    builder = Taski::InstanceBuilder.new(TestTask)
    assert builder, "InstanceBuilder should be created successfully"
  end

  def test_can_build_instance
    builder = Taski::InstanceBuilder.new(TestTask)
    instance = builder.build_instance
    assert instance, "build_instance should return an instance"
    assert_instance_of TestTask, instance
  end

  def test_builds_instance_with_dependencies
    dep_task = Class.new(Taski::Task) do
      def run
      end
    end
    Object.const_set(:BuilderDepTask, dep_task)

    main_task = Class.new(Taski::Task) do
      def run
        BuilderDepTask.ensure_instance_built
      end
    end
    Object.const_set(:BuilderMainWithDepTask, main_task)

    builder = Taski::InstanceBuilder.new(BuilderMainWithDepTask)
    instance = builder.build_instance

    assert instance, "build_instance should return an instance"
    assert_instance_of BuilderMainWithDepTask, instance
  ensure
    Object.send(:remove_const, :BuilderDepTask) if defined?(BuilderDepTask)
    Object.send(:remove_const, :BuilderMainWithDepTask) if defined?(BuilderMainWithDepTask)
  end

  def test_instance_builder_detects_circular_dependency
    task_a = Class.new(Taski::Task) do
      def run
        BuilderCircularTaskB.ensure_instance_built
      end
    end
    Object.const_set(:BuilderCircularTaskA, task_a)

    task_b = Class.new(Taski::Task) do
      def run
        BuilderCircularTaskA.ensure_instance_built
      end
    end
    Object.const_set(:BuilderCircularTaskB, task_b)

    builder = Taski::InstanceBuilder.new(BuilderCircularTaskA)

    error = assert_raises(Taski::TaskBuildError) do
      builder.build_instance
    end
    assert_includes error.message, "Circular dependency detected!"
  ensure
    Object.send(:remove_const, :BuilderCircularTaskA) if defined?(BuilderCircularTaskA)
    Object.send(:remove_const, :BuilderCircularTaskB) if defined?(BuilderCircularTaskB)
  end

  # ===================================================================
  # ENSURE INSTANCE BUILT TESTS
  # ===================================================================

  def test_ensure_instance_built_returns_singleton_instance
    # テスト開始前にリセット
    TestTask.reset!

    # 最初の呼び出しでインスタンスを作成
    instance1 = TestTask.ensure_instance_built
    assert instance1, "ensure_instance_built should return an instance"
    assert_instance_of TestTask, instance1

    # 2回目の呼び出しでは同じインスタンスを返す（シングルトン）
    instance2 = TestTask.ensure_instance_built
    assert_same instance1, instance2, "ensure_instance_built should return the same instance"
  end

  def test_ensure_instance_built_with_dependencies
    dep_task = Class.new(Taski::Task) do
      def run
        @executed = true
      end

      def executed?
        @executed
      end
    end
    Object.const_set(:EnsureDepTask, dep_task)

    main_task = Class.new(Taski::Task) do
      def run
        EnsureDepTask.ensure_instance_built
        @main_executed = true
      end

      def main_executed?
        @main_executed
      end
    end
    Object.const_set(:EnsureMainTaskWithDep, main_task)

    # メインタスクを実行
    main_instance = EnsureMainTaskWithDep.ensure_instance_built
    assert main_instance.main_executed?, "Main task should be executed"

    dep_instance = EnsureDepTask.current_instance
    assert dep_instance.executed?, "Dependency task should be executed"
  ensure
    Object.send(:remove_const, :EnsureDepTask) if defined?(EnsureDepTask)
    Object.send(:remove_const, :EnsureMainTaskWithDep) if defined?(EnsureMainTaskWithDep)
  end

  def test_ensure_instance_built_detects_circular_dependency_error
    task_a = Class.new(Taski::Task) do
      def run
        EnsureCircularDepTaskB.ensure_instance_built
      end
    end
    Object.const_set(:EnsureCircularDepTaskA, task_a)

    task_b = Class.new(Taski::Task) do
      def run
        EnsureCircularDepTaskA.ensure_instance_built
      end
    end
    Object.const_set(:EnsureCircularDepTaskB, task_b)

    error = assert_raises(Taski::TaskBuildError) do
      EnsureCircularDepTaskA.ensure_instance_built
    end
    assert_match(/Circular dependency detected/, error.message)
  ensure
    Object.send(:remove_const, :EnsureCircularDepTaskA) if defined?(EnsureCircularDepTaskA)
    Object.send(:remove_const, :EnsureCircularDepTaskB) if defined?(EnsureCircularDepTaskB)
  end

  def test_ensure_instance_built_after_reset
    instance1 = TestTask.ensure_instance_built
    assert instance1, "ensure_instance_built should return an instance"

    TestTask.reset!

    instance2 = TestTask.ensure_instance_built
    assert instance2, "ensure_instance_built should return an instance after reset"
    refute_same instance1, instance2, "ensure_instance_built should return a new instance after reset"
  end

  private

  class TestTask < Taski::Task
    def run
      @executed = true
    end

    def executed?
      @executed
    end
  end

  def setup_partial_dependency_graph
    # Skip if already set up
    return if defined?(PartialConfig)

    config_task = Class.new(Taski::Task) do
      exports :environment

      def run
        TaskiTestHelper.track_build_order("Config")
        @environment = "production"
      end
    end
    Object.const_set(:PartialConfig, config_task)

    database_task = Class.new(Taski::Task) do
      exports :connection

      def run
        TaskiTestHelper.track_build_order("Database")
        @connection = "db-#{PartialConfig.environment}"
      end
    end
    Object.const_set(:PartialDatabase, database_task)

    cache_task = Class.new(Taski::Task) do
      exports :cache_url

      def run
        TaskiTestHelper.track_build_order("Cache")
        @cache_url = "cache-#{PartialConfig.environment}"
      end
    end
    Object.const_set(:PartialCache, cache_task)

    app_task = Class.new(Taski::Task) do
      def run
        TaskiTestHelper.track_build_order("Application")
        # Use both database and cache
        @db = PartialDatabase.connection
        @cache = PartialCache.cache_url
      end
    end
    Object.const_set(:PartialApplication, app_task)
  end

  def setup_mixed_build_chain
    # Skip if already set up
    return if defined?(MixedChainRoot)

    # Root task (singleton build)
    root_task = Class.new(Taski::Task) do
      exports :root_value

      def run
        TaskiTestHelper.track_build_order("Root")
        @root_value = "root"
      end
    end
    Object.const_set(:MixedChainRoot, root_task)

    # Middle task (parametrized build)
    param_task = Class.new(Taski::Task) do
      exports :param_value

      def self.name
        "MixedChainParam"
      end

      def run
        args = build_args
        mode = args[:mode] || "default"
        TaskiTestHelper.track_build_order("Param-#{mode}")
        @param_value = "param-#{mode}-#{MixedChainRoot.root_value}"
      end
    end
    Object.const_set(:MixedChainParam, param_task)

    # Final task (singleton build)
    final_task = Class.new(Taski::Task) do
      exports :final_value

      def run
        TaskiTestHelper.track_build_order("Final")
        # Use parametrized build of middle task
        param_result = MixedChainParam.run(mode: "fast")
        @final_value = "final-#{param_result.param_value}"
      end
    end
    Object.const_set(:MixedChainFinal, final_task)
  end
end
