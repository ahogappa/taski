# frozen_string_literal: true

require_relative "test_helper"

class TestExportsAPI < Minitest::Test
  include TaskiTestHelper

  def setup
    setup_taski_test
  end

  # === Exports API Tests ===
  # Test static dependency resolution and instance variable exports

  def test_exports_api_dependency_chain
    # Test exports API with dependency chain
    task_a = Class.new(Taski::Task) do
      exports :task_a_result

      def build
        TaskiTestHelper.track_build_order("ExportTaskA")
        @task_a_result = "Task A"
      end
    end
    Object.const_set(:ExportTaskA, task_a)

    task_b = Class.new(Taski::Task) do
      exports :task_b_result

      def build
        TaskiTestHelper.track_build_order("ExportTaskB")
        @task_b_result = "Task B with #{ExportTaskA.task_a_result}"
      end
    end
    Object.const_set(:ExportTaskB, task_b)

    task_c = Class.new(Taski::Task) do
      exports :task_c_result

      def build
        TaskiTestHelper.track_build_order("ExportTaskC")
        @task_c_result = "Task C with #{ExportTaskA.task_a_result} and #{ExportTaskB.task_b_result}"
      end
    end
    Object.const_set(:ExportTaskC, task_c)

    # Reset and build
    TaskiTestHelper.reset_build_order
    ExportTaskC.build

    # Verify build order
    build_order = TaskiTestHelper.build_order
    unique_tasks = build_order.uniq
    assert_equal 3, unique_tasks.size, "Expected 3 unique tasks to be built"

    task_a_idx = build_order.index("ExportTaskA")
    task_b_idx = build_order.index("ExportTaskB")
    task_c_idx = build_order.index("ExportTaskC")

    assert task_a_idx < task_b_idx, "ExportTaskA should be built before ExportTaskB"
    assert task_b_idx < task_c_idx, "ExportTaskB should be built before ExportTaskC"

    # Verify exported values
    assert_equal "Task A", ExportTaskA.task_a_result
    assert_equal "Task B with Task A", ExportTaskB.task_b_result
    assert_equal "Task C with Task A and Task B with Task A", ExportTaskC.task_c_result
  end

  def test_exports_with_existing_method
    # Test exports when method already exists
    task = Class.new(Taski::Task) do
      # Define method before exports
      def self.existing_method
        "original"
      end

      exports :existing_method, :new_method

      def build
        @existing_method = "exported"
        @new_method = "new"
      end
    end
    Object.const_set(:ExistingMethodTask, task)

    # Original method should not be overridden
    assert_equal "original", ExistingMethodTask.existing_method

    # New method should work
    ExistingMethodTask.build
    assert_equal "new", ExistingMethodTask.new_method
  end

  def test_multiple_instance_variables_exports
    # Test exports with multiple instance variables
    task = Class.new(Taski::Task) do
      exports :task_name, :version, :config

      def build
        @task_name = "MultiTask"
        @version = "1.0.0"
        @config = {debug: true, timeout: 30}
      end
    end
    Object.const_set(:MultiExportTask, task)

    # Build and verify all exports work
    MultiExportTask.build

    assert_equal "MultiTask", MultiExportTask.task_name
    assert_equal "1.0.0", MultiExportTask.version
    assert_equal({debug: true, timeout: 30}, MultiExportTask.config)

    # Verify instance methods also work
    instance = MultiExportTask.new
    instance.build
    assert_equal "MultiTask", instance.task_name
    assert_equal "1.0.0", instance.version
    assert_equal({debug: true, timeout: 30}, instance.config)
  end

  def test_inheritance_with_exports
    # Test that exports work properly with inheritance
    base_task = Class.new(Taski::Task) do
      exports :base_value

      def build
        @base_value = "base"
      end
    end
    Object.const_set(:BaseTaskA, base_task)

    derived_task = Class.new(BaseTaskA) do
      exports :derived_value

      def build
        super
        @derived_value = "derived with #{base_value}"
      end
    end
    Object.const_set(:DerivedTaskA, derived_task)

    # Build derived task
    DerivedTaskA.build

    # Both base and derived values should be accessible
    assert_equal "base", DerivedTaskA.base_value
    assert_equal "derived with base", DerivedTaskA.derived_value
  end
end
