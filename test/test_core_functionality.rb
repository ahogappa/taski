# frozen_string_literal: true

require_relative "test_helper"

class TestCoreFunctionality < Minitest::Test
  include TaskiTestHelper

  def setup
    setup_taski_test
  end

  # ==============================
  # === Exports API Tests ===
  # ==============================
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

  # ==============================
  # === Define API Tests ===
  # ==============================
  # Test dynamic dependency resolution and lazy evaluation

  def test_define_api_simple
    # Test basic define API functionality
    task_a = Class.new(Taski::Task) do
      define :task_a, -> { "Task A" }

      def build
        TaskiTestHelper.track_build_order("SimpleTaskA")
        puts task_a
      end
    end
    Object.const_set(:SimpleTaskA, task_a)

    task_b = Class.new(Taski::Task) do
      define :simple_task, -> { "Task result is #{SimpleTaskA.task_a}" }

      def build
        TaskiTestHelper.track_build_order("SimpleTaskB")
        puts simple_task
      end
    end
    Object.const_set(:SimpleTaskB, task_b)

    # Reset build order tracking
    TaskiTestHelper.reset_build_order

    assert_output("Task A\nTask result is Task A\n") { SimpleTaskB.build }

    # Verify build order
    build_order = TaskiTestHelper.build_order
    task_a_idx = build_order.index("SimpleTaskA")
    task_b_idx = build_order.index("SimpleTaskB")
    assert task_a_idx < task_b_idx, "SimpleTaskA should be built before SimpleTaskB"
  end

  def test_define_api_basic_dependency_resolution
    # Test that define API can resolve basic multi-layer dependencies
    base_component = Class.new(Taski::Task) do
      define :compile, -> { "Base component compiled" }

      def build
        puts compile
        "base-built"
      end
    end
    Object.const_set(:BaseComponent, base_component)

    frontend = Class.new(Taski::Task) do
      define :build_ui, -> { "Frontend UI built using #{BaseComponent.compile}" }

      def build
        puts build_ui
        "frontend-built"
      end
    end
    Object.const_set(:Frontend, frontend)

    # Execute frontend build which should trigger BaseComponent dependency
    output = capture_io { Frontend.build }

    # Verify that dependency was resolved and both tasks executed
    assert_includes output[0], "Base component compiled"
    assert_includes output[0], "Frontend UI built using Base component compiled"
  end

  def test_define_api_dependency_execution_order
    # Test that define API executes dependencies in correct order
    base_component = Class.new(Taski::Task) do
      define :compile, -> { "Base component compiled" }

      def build
        TaskiTestHelper.track_build_order("BaseComponent")
        puts compile
      end
    end
    Object.const_set(:BaseComponent, base_component)

    frontend = Class.new(Taski::Task) do
      define :build_ui, -> { "Frontend UI built using #{BaseComponent.compile}" }

      def build
        TaskiTestHelper.track_build_order("Frontend")
        puts build_ui
      end
    end
    Object.const_set(:Frontend, frontend)

    application = Class.new(Taski::Task) do
      define :build_app, -> { "Application built with: #{Frontend.build_ui}" }

      def build
        TaskiTestHelper.track_build_order("Application")
        puts build_app
      end
    end
    Object.const_set(:Application, application)

    TaskiTestHelper.reset_build_order
    capture_io { Application.build }

    # Verify execution order
    build_order = TaskiTestHelper.build_order
    base_idx = build_order.index("BaseComponent")
    frontend_idx = build_order.index("Frontend")
    app_idx = build_order.index("Application")

    assert base_idx < frontend_idx, "BaseComponent should be built before Frontend"
    assert frontend_idx < app_idx, "Frontend should be built before Application"
  end

  def test_define_api_dependency_deduplication
    # Test that define API executes shared dependencies only once
    base_component = Class.new(Taski::Task) do
      define :compile, -> { "Base component compiled" }

      def build
        TaskiTestHelper.track_build_order("BaseComponent")
        puts compile
      end
    end
    Object.const_set(:BaseComponent, base_component)

    frontend = Class.new(Taski::Task) do
      define :build_ui, -> { "Frontend UI built using #{BaseComponent.compile}" }

      def build
        TaskiTestHelper.track_build_order("Frontend")
        puts build_ui
      end
    end
    Object.const_set(:Frontend, frontend)

    backend = Class.new(Taski::Task) do
      define :build_api, -> { "Backend API built using #{BaseComponent.compile}" }

      def build
        TaskiTestHelper.track_build_order("Backend")
        puts build_api
      end
    end
    Object.const_set(:Backend, backend)

    application = Class.new(Taski::Task) do
      define :build_app, -> {
        "Application built with:\n- #{Frontend.build_ui}\n- #{Backend.build_api}"
      }

      def build
        TaskiTestHelper.track_build_order("Application")
        puts build_app
      end
    end
    Object.const_set(:Application, application)

    TaskiTestHelper.reset_build_order
    capture_io { Application.build }

    # Verify BaseComponent was built exactly once despite being a dependency of both Frontend and Backend
    build_order = TaskiTestHelper.build_order
    assert_equal 1, build_order.count("BaseComponent"), "BaseComponent should be built exactly once"

    # Verify all components were built
    assert_includes build_order, "BaseComponent"
    assert_includes build_order, "Frontend"
    assert_includes build_order, "Backend"
    assert_includes build_order, "Application"
  end

  def test_define_with_options
    # Test define API with options parameter
    task = Class.new(Taski::Task) do
      define :task_with_options, -> { "value with options" }, priority: :high

      def build
        puts task_with_options
      end
    end
    Object.const_set(:OptionsTaskA, task)

    # Build to create the method and then test value
    capture_io { OptionsTaskA.build }
    assert_equal "value with options", OptionsTaskA.task_with_options

    # Options functionality is tested implicitly through the behavior
  end

  # ==============================
  # === Lifecycle Tests ===
  # ==============================

  def test_clean_without_build
    # Test that clean works even when build was never called
    task_a = Class.new(Taski::Task) do
      exports :value

      def build
        @value = "built"
        puts "TaskA build"
      end

      def clean
        puts "TaskA clean (value: #{@value || "not built"})"
      end
    end
    Object.const_set(:CleanTaskA, task_a)

    task_b = Class.new(Taski::Task) do
      def build
        puts "TaskB build with #{CleanTaskA.value}"
      end

      def clean
        puts "TaskB clean"
      end
    end
    Object.const_set(:CleanTaskB, task_b)

    # Call clean without building first
    output = capture_io { CleanTaskB.clean }

    # Verify clean was called but build was not
    assert_includes output[0], "TaskB clean"
    assert_includes output[0], "TaskA clean (value: not built)"
    refute_includes output[0], "TaskA build"
    refute_includes output[0], "TaskB build"
  end

  def test_refresh_functionality
    # Test that refresh works like reset
    task = Class.new(Taski::Task) do
      exports :value

      def build
        @value = "refreshed_#{object_id}"
      end
    end
    Object.const_set(:RefreshTaskA, task)

    # Build the task
    first_value = RefreshTaskA.value

    # Refresh the task
    result = RefreshTaskA.refresh

    # Should return self
    assert_equal RefreshTaskA, result

    # Build again - should create new instance with different value
    second_value = RefreshTaskA.value

    # Values should be different (different object_id)
    refute_equal first_value, second_value
  end

  def test_task_reset_functionality
    # Test that reset! clears cached instances
    task = Class.new(Taski::Task) do
      exports :value

      def build
        @value = "built_#{object_id}"
      end
    end
    Object.const_set(:ResetTaskA, task)

    # Build the task
    first_value = ResetTaskA.value

    # Reset the task
    ResetTaskA.reset!

    # Build again - should create new instance with different value
    second_value = ResetTaskA.value

    # Values should be different (different object_id)
    refute_equal first_value, second_value
  end

  def test_circular_dependency_detection
    # Test that circular dependencies are properly detected and raise an error
    task_a = Class.new(Taski::Task) do
      exports :result_a

      def build
        puts "CircularTaskA"
        @result_a = CircularTaskB.build.result_b
      end
    end
    Object.const_set(:CircularTaskA, task_a)

    task_b = Class.new(Taski::Task) do
      exports :result_b

      def build
        puts "CircularTaskB"
        @result_b = CircularTaskA.build.result_a
      end
    end
    Object.const_set(:CircularTaskB, task_b)

    # Attempting to build should raise TaskBuildError with circular dependency message
    error = assert_raises(Taski::TaskBuildError) do
      CircularTaskA.build
    end
    assert_includes error.message, "Circular dependency detected"
  end

  def test_method_visibility
    # Test that private methods are properly hidden
    refute Taski::Task.respond_to?(:build_monitor), "build_monitor should be private"
    refute Taski::Task.respond_to?(:build_thread_key), "build_thread_key should be private"
    refute Taski::Task.respond_to?(:extract_class), "extract_class should be private"

    # Test that public methods are accessible
    assert Taski::Task.respond_to?(:build), "build should be public"
    assert Taski::Task.respond_to?(:clean), "clean should be public"
    assert Taski::Task.respond_to?(:reset!), "reset! should be public"
    assert Taski::Task.respond_to?(:refresh), "refresh should be public"
  end
end
