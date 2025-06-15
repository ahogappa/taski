# frozen_string_literal: true

require_relative "test_helper"

class TestDefineAPI < Minitest::Test
  include TaskiTestHelper

  def setup
    setup_taski_test
  end

  # === Define API Tests ===
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

  def test_define_api_complex_dependencies
    # Test complex dependency graph using define API
    base_component = Class.new(Taski::Task) do
      define :compile, -> { "Base component compiled" }

      def build
        TaskiTestHelper.track_build_order("BaseComponent")
        puts compile
      end
    end
    Object.const_set(:BaseComponent, base_component)

    # Frontend and Backend both depend on BaseComponent
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

    # Database with no dependencies
    database = Class.new(Taski::Task) do
      define :setup_db, -> { "Database initialized" }

      def build
        TaskiTestHelper.track_build_order("Database")
        puts setup_db
      end
    end
    Object.const_set(:Database, database)

    # Application depends on all components
    application = Class.new(Taski::Task) do
      define :build_app, -> {
        "Application built with:\n- #{Frontend.build_ui}\n- #{Backend.build_api}\n- #{Database.setup_db}"
      }

      def build
        TaskiTestHelper.track_build_order("Application")
        puts build_app
      end
    end
    Object.const_set(:Application, application)

    # Deploy depends on Application
    deploy = Class.new(Taski::Task) do
      define :deploy_app, -> { "Deploying: #{Application.build_app}" }

      def build
        TaskiTestHelper.track_build_order("Deploy")
        puts deploy_app
      end
    end
    Object.const_set(:Deploy, deploy)

    # Reset and execute
    TaskiTestHelper.reset_build_order

    output = capture_io { Deploy.build }

    # Verify output
    assert_includes output[0], "Base component compiled"
    assert_includes output[0], "Frontend UI built"
    assert_includes output[0], "Backend API built"
    assert_includes output[0], "Database initialized"
    assert_includes output[0], "Application built with"
    assert_includes output[0], "Deploying"

    # Verify build order
    build_order = TaskiTestHelper.build_order
    base_idx = build_order.index("BaseComponent")
    frontend_idx = build_order.index("Frontend")
    backend_idx = build_order.index("Backend")
    db_idx = build_order.index("Database")
    app_idx = build_order.index("Application")
    deploy_idx = build_order.index("Deploy")

    # BaseComponent should be built before Frontend and Backend
    assert base_idx < frontend_idx, "BaseComponent should be built before Frontend"
    assert base_idx < backend_idx, "BaseComponent should be built before Backend"

    # All components should be built before Application
    assert frontend_idx < app_idx, "Frontend should be built before Application"
    assert backend_idx < app_idx, "Backend should be built before Application"
    assert db_idx < app_idx, "Database should be built before Application"

    # Application should be built before Deploy
    assert app_idx < deploy_idx, "Application should be built before Deploy"

    # BaseComponent should only be built once
    assert_equal 1, build_order.count("BaseComponent"), "BaseComponent should be built exactly once"
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

    # Check that options are stored
    definitions = OptionsTaskA.instance_variable_get(:@definitions)
    assert_equal :high, definitions[:task_with_options][:options][:priority]

    # Build to create the method and then test value
    capture_io { OptionsTaskA.build }
    assert_equal "value with options", OptionsTaskA.task_with_options
  end

  def test_mixed_define_and_exports_apis
    # Test mixing dynamic (define) and static (exports) APIs
    task_d = Class.new(Taski::Task) do
      define :legacy_value, -> { "Legacy Value" }

      def build
        TaskiTestHelper.track_build_order("TaskD")
        puts legacy_value
      end
    end
    Object.const_set(:TaskD, task_d)

    # Exports API task depending on define API task
    task_e = Class.new(Taski::Task) do
      exports :modern_value

      def build
        TaskiTestHelper.track_build_order("TaskE")
        @modern_value = "Modern with #{TaskD.legacy_value}"
      end
    end
    Object.const_set(:TaskE, task_e)

    # Define API task depending on exports API task
    task_f = Class.new(Taski::Task) do
      define :combined_value, -> { "Combined: #{TaskE.modern_value}" }

      def build
        TaskiTestHelper.track_build_order("TaskF")
        puts combined_value
      end
    end
    Object.const_set(:TaskF, task_f)

    # Reset and build
    TaskiTestHelper.reset_build_order
    capture_io { TaskF.build }

    # Verify build order
    build_order = TaskiTestHelper.build_order
    task_d_idx = build_order.index("TaskD")
    task_e_idx = build_order.index("TaskE")

    if task_e_idx
      assert task_d_idx < task_e_idx, "TaskD should be built before TaskE"
    end
    
    # Verify values
    assert_equal "Legacy Value", TaskD.legacy_value
    assert_equal "Modern with Legacy Value", TaskE.modern_value
    assert_equal "Combined: Modern with Legacy Value", TaskF.combined_value
  end

  def test_dynamic_dependency_resolution
    # Test define API with runtime-dependent class selection
    
    # Mock service classes
    old_service = Class.new(Taski::Task) do
      exports :service_result
      def build
        @service_result = "old-service-result"
      end
    end
    Object.const_set(:OldService, old_service)

    new_service = Class.new(Taski::Task) do
      exports :service_result  
      def build
        @service_result = "new-service-result"
      end
    end
    Object.const_set(:NewService, new_service)

    # Task that dynamically chooses service based on environment
    dynamic_task = Class.new(Taski::Task) do
      define :selected_service_result, -> {
        # Simulate environment-based service selection
        service = ENV['USE_NEW_SERVICE'] == 'true' ? NewService : OldService
        service.service_result
      }

      def build
        puts "Using: #{selected_service_result}"
      end
    end
    Object.const_set(:DynamicTask, dynamic_task)

    # Test with old service
    ENV['USE_NEW_SERVICE'] = 'false'
    capture_io { DynamicTask.build }
    assert_equal "old-service-result", DynamicTask.selected_service_result

    # Reset and test with new service
    DynamicTask.reset!
    ENV['USE_NEW_SERVICE'] = 'true' 
    capture_io { DynamicTask.build }
    assert_equal "new-service-result", DynamicTask.selected_service_result

    # Clean up
    ENV.delete('USE_NEW_SERVICE')
  end
end