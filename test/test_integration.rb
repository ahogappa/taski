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

    # Dependent task with explicit dependency
    dependent_task = Class.new(Taski::Task) do
      # Explicitly set dependency
      @dependencies = [{ klass: BaseTask }]

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

    # Exports API task with explicit dependency
    exports_task = Class.new(Taski::Task) do
      @dependencies = [{ klass: DefineTask }]
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
    
    task = Class.new(Taski::Task) do
      exports :timestamp

      def build
        @timestamp = Time.now.to_f
      end
    end
    Object.const_set(:TimestampTask, task)

    # Build first time
    TimestampTask.build
    first_timestamp = TimestampTask.timestamp

    # Small delay to ensure different timestamp
    sleep 0.01

    # Reset and build again
    TimestampTask.reset!
    TimestampTask.build
    second_timestamp = TimestampTask.timestamp

    # Should have different timestamps
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
      @dependencies = [{ klass: FailingIntegrationTask }]

      def build
        puts "This should not execute"
      end
    end
    Object.const_set(:DependentIntegrationTask, dependent_task)

    # Should raise TaskBuildError
    assert_raises(Taski::TaskBuildError) do
      DependentIntegrationTask.build
    end
  end
end