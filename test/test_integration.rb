# frozen_string_literal: true

require_relative "test_helper"

class TestIntegration < Minitest::Test
  include TaskiTestHelper

  def setup
    setup_taski_test
  end

  # === Integration Tests ===

  def test_simple_integration_workflow
    # Test a simple workflow with explicit dependencies

    # Base task
    base_task = Class.new(Taski::Task) do
      exports :config

      def build
        TaskiTestHelper.track_build_order("BaseTask")
        @config = "base-config"
      end
    end
    Object.const_set(:BaseTask, base_task)

    # Dependent task that naturally depends on BaseTask
    dependent_task = Class.new(Taski::Task) do
      exports :result

      def build
        TaskiTestHelper.track_build_order("DependentTask")
        @result = "result-using-#{BaseTask.config}"
      end
    end
    Object.const_set(:DependentTask, dependent_task)

    # Reset and build
    TaskiTestHelper.reset_build_order
    DependentTask.build

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

      def build
        TaskiTestHelper.track_build_order("DefineTask")
        puts shared_value
      end
    end
    Object.const_set(:DefineTask, define_task)

    # Exports API task that depends on DefineTask
    exports_task = Class.new(Taski::Task) do
      exports :combined_result

      def build
        TaskiTestHelper.track_build_order("ExportsTask")
        @combined_result = "exports-#{DefineTask.shared_value}"
      end
    end
    Object.const_set(:ExportsTask, exports_task)

    # Reset and build
    TaskiTestHelper.reset_build_order
    capture_io { ExportsTask.build }

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

      define_method :build do
        build_counter += 1
        @build_number = build_counter
        @timestamp = Time.now.to_f
      end
    end
    Object.const_set(:TimestampTask, task)

    # Build first time
    TimestampTask.build
    first_timestamp = TimestampTask.timestamp
    first_build_number = TimestampTask.build_number

    # Reset and build again
    TimestampTask.reset!
    TimestampTask.build
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
      def build
        raise StandardError, "Integration test failure"
      end
    end
    Object.const_set(:FailingIntegrationTask, failing_task)

    dependent_task = Class.new(Taski::Task) do
      def build
        # This will create a natural dependency on FailingIntegrationTask
        # and should never execute because FailingIntegrationTask will fail first
        FailingIntegrationTask.build
        puts "This should not execute"
      end
    end
    Object.const_set(:DependentIntegrationTask, dependent_task)

    # Should raise TaskBuildError
    assert_raises(Taski::TaskBuildError) do
      DependentIntegrationTask.build
    end
  end

  def test_granular_task_execution
    # Test that individual tasks can be executed independently

    # Create a dependency chain: A -> B -> C
    task_a = Class.new(Taski::Task) do
      exports :value_a

      def build
        TaskiTestHelper.track_build_order("TaskA")
        @value_a = "A"
      end
    end
    Object.const_set(:GranularTaskA, task_a)

    task_b = Class.new(Taski::Task) do
      exports :value_b

      def build
        TaskiTestHelper.track_build_order("TaskB")
        @value_b = "B-#{GranularTaskA.value_a}"
      end
    end
    Object.const_set(:GranularTaskB, task_b)

    task_c = Class.new(Taski::Task) do
      exports :value_c

      def build
        TaskiTestHelper.track_build_order("TaskC")
        @value_c = "C-#{GranularTaskB.value_b}"
      end
    end
    Object.const_set(:GranularTaskC, task_c)

    # Test 1: Build only TaskA
    TaskiTestHelper.reset_build_order
    GranularTaskA.build

    assert_equal ["TaskA"], TaskiTestHelper.build_order
    assert_equal "A", GranularTaskA.value_a

    # Test 2: Build TaskB (should also build TaskA if not already built)
    GranularTaskA.reset!
    GranularTaskB.reset!
    TaskiTestHelper.reset_build_order
    GranularTaskB.build

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

  def test_partial_dependency_graph_execution
    # Test that we can execute from any point in the dependency graph

    # Create a more complex graph:
    #     Config
    #    /      \
    # Database  Cache
    #    \      /
    #   Application

    config_task = Class.new(Taski::Task) do
      exports :environment

      def build
        TaskiTestHelper.track_build_order("Config")
        @environment = "production"
      end
    end
    Object.const_set(:PartialConfig, config_task)

    database_task = Class.new(Taski::Task) do
      exports :connection

      def build
        TaskiTestHelper.track_build_order("Database")
        @connection = "db-#{PartialConfig.environment}"
      end
    end
    Object.const_set(:PartialDatabase, database_task)

    cache_task = Class.new(Taski::Task) do
      exports :cache_url

      def build
        TaskiTestHelper.track_build_order("Cache")
        @cache_url = "cache-#{PartialConfig.environment}"
      end
    end
    Object.const_set(:PartialCache, cache_task)

    app_task = Class.new(Taski::Task) do
      def build
        TaskiTestHelper.track_build_order("Application")
        # Use both database and cache
        @db = PartialDatabase.connection
        @cache = PartialCache.cache_url
      end
    end
    Object.const_set(:PartialApplication, app_task)

    # Test: Build only Database branch
    TaskiTestHelper.reset_build_order
    PartialDatabase.build

    assert_equal ["Config", "Database"], TaskiTestHelper.build_order
    assert_equal "db-production", PartialDatabase.connection

    # Cache should not be built
    refute_includes TaskiTestHelper.build_order, "Cache"

    # Test: Build only Cache branch (after reset)
    PartialConfig.reset!
    PartialCache.reset!
    TaskiTestHelper.reset_build_order
    PartialCache.build

    assert_equal ["Config", "Cache"], TaskiTestHelper.build_order
    assert_equal "cache-production", PartialCache.cache_url

    # Database should not be built
    refute_includes TaskiTestHelper.build_order, "Database"
  end
end
