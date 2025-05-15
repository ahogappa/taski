# frozen_string_literal: true

require "minitest/autorun"
require "timeout"
require_relative "../lib/taski"
require 'debug'

class TestTaski < Minitest::Test
  # Class methods for tracking build order
  @build_order = []

  def self.track_build_order(component)
    @build_order ||= []
    @build_order << component
  end

  def self.build_order
    @build_order || []
  end

  def self.reset_build_order
    @build_order = []
  end

  def test_reference_class
    # Test the Reference class functionality
    ref = Taski::Reference.new("String")

    assert_instance_of Taski::Reference, ref
    assert_equal "String", ref.instance_variable_get(:@klass)
    assert_equal String, ref.deref
    assert_equal "&String", ref.inspect
  end

  def test_task_ref_method
    # Test the ref method in Task class
    reference = catch(:unresolve) do
      Taski::Task.ref("String")
      nil
    end

    assert_instance_of Taski::Reference, reference
    assert_equal "String", reference.instance_variable_get(:@klass)
    assert_equal String, reference.deref
    assert_equal "&String", reference.inspect
  end

  def test_simple_task
    task_a = Class.new(Taski::Task) do
      definition :task_a, -> { "Task A" }

      def build
        puts task_a
      end
    end
    Object.const_set(:TaskA, task_a)

    task_b = Class.new(Taski::Task) do
      definition :simple_task, -> { "Task result is #{TaskA.task_a}" }

      def build
        puts simple_task
      end
    end
    Object.const_set(:TaskB, task_b)
debugger
    assert_output("Task A\nTask result is Task A\n") { TaskB.build }
  end

  def test_complex_task_dependencies
    # Setup a complex task dependency graph with build order tracking

    # Base component that others depend on
    base_component = Class.new(Taski::Task) do
      definition :compile, -> { "Base component compiled" }

      def build
        # Record build order
        TestTaski.track_build_order("BaseComponent")
        puts compile
      end
    end
    Object.const_set(:BaseComponent, base_component)

    # Frontend component depending on the base
    frontend = Class.new(Taski::Task) do
      definition :build_ui, -> {
        # Direct reference to base component
        "Frontend UI built using #{BaseComponent.compile}"
      }

      def build
        TestTaski.track_build_order("Frontend")
        puts build_ui
      end
    end
    Object.const_set(:Frontend, frontend)

    # Backend component also depending on the base
    backend = Class.new(Taski::Task) do
      definition :build_api, -> {
        # Direct reference to base component
        "Backend API built using #{BaseComponent.compile}"
      }

      def build
        TestTaski.track_build_order("Backend")
        puts build_api
      end
    end
    Object.const_set(:Backend, backend)

    # Database component with no dependencies
    database = Class.new(Taski::Task) do
      definition :setup_db, -> { "Database initialized" }

      def build
        TestTaski.track_build_order("Database")
        puts setup_db
      end
    end
    Object.const_set(:Database, database)

    # Main application that depends on frontend, backend, and database
    application = Class.new(Taski::Task) do
      definition :build_app, -> {
        # Direct references to all dependencies
        "Application built with:\n- #{Frontend.build_ui}\n- #{Backend.build_api}\n- #{Database.setup_db}"
      }

      def build
        TestTaski.track_build_order("Application")
        puts build_app
      end
    end
    Object.const_set(:Application, application)

    # Deploy task that depends on the application
    deploy = Class.new(Taski::Task) do
      definition :deploy_app, -> {
        # Direct reference to application
        "Deploying: #{Application.build_app}"
      }

      def build
        TestTaski.track_build_order("Deploy")
        puts deploy_app
      end
    end
    Object.const_set(:Deploy, deploy)

    begin
      # Register the task classes

      # Clear tracking
      TestTaski.reset_build_order

      # Execute the deploy task which should build everything in correct order
      output = capture_io do
        Deploy.build
      end

      # Verify the output contains expected results
      assert_includes output[0], "Base component compiled"
      assert_includes output[0], "Frontend UI built"
      assert_includes output[0], "Backend API built"
      assert_includes output[0], "Database initialized"
      assert_includes output[0], "Application built with"
      assert_includes output[0], "Deploying"

      # Verify the build order - base component should be built before frontend/backend
      base_idx = TestTaski.build_order.index("BaseComponent")
      frontend_idx = TestTaski.build_order.index("Frontend")
      backend_idx = TestTaski.build_order.index("Backend")
      db_idx = TestTaski.build_order.index("Database")
      app_idx = TestTaski.build_order.index("Application")
      deploy_idx = TestTaski.build_order.index("Deploy")

      # Base component should be built before frontend and backend
      assert base_idx < frontend_idx, "BaseComponent should be built before Frontend"
      assert base_idx < backend_idx, "BaseComponent should be built before Backend"

      # Frontend, backend, and database should be built before application
      assert frontend_idx < app_idx, "Frontend should be built before Application"
      assert backend_idx < app_idx, "Backend should be built before Application"
      assert db_idx < app_idx, "Database should be built before Application"

      # Application should be built before deploy
      assert app_idx < deploy_idx, "Application should be built before Deploy"

      # BaseComponent should only be built once even though it's referenced multiple times
      assert_equal 1, TestTaski.build_order.count("BaseComponent"),
                 "BaseComponent should be built exactly once"
    ensure
      # Clean up test constants
      [
        :BaseComponent, :Frontend, :Backend, :Database,
        :Application, :Deploy
      ].each do |const|
        Object.send(:remove_const, const) if Object.const_defined?(const)
      end
    end
  end

  # def test_circular_dependency_detection
  #   # Test case to verify that circular dependencies are properly handled

  #   # Create two tasks that circularly depend on each other
  #   task_a = Class.new(Taski::Task) do
  #     definition :task_a_method, -> {
  #       b = ref("CircularTaskB")
  #       "Task A depends on #{b.task_b_method}"
  #     }

  #     def build
  #       puts task_a_method
  #     end
  #   end

  #   task_b = Class.new(Taski::Task) do
  #     definition :task_b_method, -> {
  #       a = ref("CircularTaskA")
  #       "Task B depends on #{a.task_a_method}"
  #     }

  #     def build
  #       puts task_b_method
  #     end
  #   end

  #   begin
  #     Object.const_set(:CircularTaskA, task_a)
  #     Object.const_set(:CircularTaskB, task_b)

  #     # With circular dependencies, we expect the system to either:
  #     # 1. Detect and report the circular dependency, or
  #     # 2. Enter an infinite recursion (which we'll prevent with timeout)

  #     # Use a timeout to prevent test from hanging
  #     Timeout.timeout(1) do
  #       assert_raises(SystemStackError, "Should detect circular dependency") do
  #         task_a.build
  #       end
  #     end
  #   rescue Timeout::Error
  #     flunk "Test timed out - likely due to unresolved circular dependency"
  #   ensure
  #     [:CircularTaskA, :CircularTaskB].each do |const|
  #       Object.send(:remove_const, const) if Object.const_defined?(const)
  #     end
  #   end
  # end
end
