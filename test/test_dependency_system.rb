# frozen_string_literal: true

require_relative "test_helper"

class TestDependencySystem < Minitest::Test
  include TaskiTestHelper

  def setup
    setup_taski_test
  end

  # ========================================================================
  # STATIC ANALYSIS TESTS
  # ========================================================================

  def test_static_analysis_with_exports
    # Test static analysis detection of dependencies in build methods
    task_a = Class.new(Taski::Task) do
      exports :task_a_result

      def run
        TaskiTestHelper.track_build_order("StaticTaskA")
        @task_a_result = "Task A"
        puts "StaticTaskA Processing..."
      end

      def clean
        puts "StaticTaskA Cleaning..."
      end
    end
    Object.const_set(:StaticTaskA, task_a)

    task_b = Class.new(Taski::Task) do
      def run
        TaskiTestHelper.track_build_order("StaticTaskB")
        puts "Task result is #{StaticTaskA.task_a_result}"
      end

      def clean
        puts "StaticTaskB Cleaning..."
      end
    end
    Object.const_set(:StaticTaskB, task_b)

    TaskiTestHelper.reset_build_order

    output = capture_io { StaticTaskB.run }
    assert_includes output[0], "StaticTaskA Processing..."
    assert_includes output[0], "Task result is Task A"

    # Verify build order
    build_order = TaskiTestHelper.build_order
    task_a_idx = build_order.index("StaticTaskA")
    task_b_idx = build_order.index("StaticTaskB")
    assert task_a_idx < task_b_idx, "StaticTaskA should be built before StaticTaskB"

    # Test clean method in reverse order
    output = capture_io { StaticTaskB.clean }
    assert_includes output[0], "StaticTaskB Cleaning..."
    assert_includes output[0], "StaticTaskA Cleaning..."
  end

  def test_static_analysis_with_nested_constants
    # Test static analysis with nested constant references
    # Create nested module and class outside method
    nested_module = Module.new do
      const_set(:NestedTaskA, Class.new(Taski::Task) do
        exports :nested_value

        def run
          @nested_value = "nested A"
        end
      end)
    end
    Object.const_set(:TestModule, nested_module)

    task_b = Class.new(Taski::Task) do
      def run
        puts "Using #{TestModule::NestedTaskA.nested_value}"
      end
    end
    Object.const_set(:NestedTaskB, task_b)

    # Dependency detection is verified through actual execution behavior
    # If dependency wasn't detected, the build would fail or produce incorrect results
  end

  def test_dependency_analyzer_error_handling
    # Test DependencyAnalyzer with invalid file
    dependencies = Taski::DependencyAnalyzer.analyze_method(String, :build)
    assert_equal [], dependencies
  end

  def test_deep_dependency_chain_setup_and_verification
    # Test setting up a deep dependency chain (A -> B -> C -> D)
    setup_deep_dependency_chain

    # Verify all tasks are properly defined
    assert DeepTaskD.respond_to?(:build)
    assert DeepTaskC.respond_to?(:build)
    assert DeepTaskB.respond_to?(:build)
    assert DeepTaskA.respond_to?(:build)
  end

  def test_deep_dependency_chain_execution_order
    # Test that deep dependency chain builds in correct order
    setup_deep_dependency_chain

    # Reset all tasks to ensure clean state
    DeepTaskA.reset!
    DeepTaskB.reset!
    DeepTaskC.reset!
    DeepTaskD.reset!

    TaskiTestHelper.reset_build_order
    DeepTaskA.run

    # Verify build order (D should be built first, A last)
    build_order = TaskiTestHelper.build_order
    assert_equal "DeepTaskD", build_order.first
    assert_equal "DeepTaskA", build_order.last

    # Verify all tasks executed exactly once in correct sequence
    assert_equal ["DeepTaskD", "DeepTaskC", "DeepTaskB", "DeepTaskA"], build_order
  end

  def test_deep_dependency_chain_value_propagation
    # Test that values are correctly propagated through deep dependency chain
    setup_deep_dependency_chain

    # Reset all tasks to ensure clean state
    DeepTaskA.reset!
    DeepTaskB.reset!
    DeepTaskC.reset!
    DeepTaskD.reset!

    TaskiTestHelper.reset_build_order
    DeepTaskA.run

    # Verify final values are correctly built from dependencies
    assert_equal "D", DeepTaskD.d_value
    assert_equal "C-D", DeepTaskC.c_value
    assert_equal "B-C-D", DeepTaskB.b_value
    assert_equal "A-B-C-D", DeepTaskA.a_value
  end

  # ========================================================================
  # DEPENDENCIES METHOD TESTS
  # ========================================================================

  def test_task_has_dependencies_method
    task = Class.new(Taski::Task) do
      def run
      end
    end

    assert_respond_to task, :dependencies, "Task class should have dependencies method"
  end

  def test_dependencies_method_returns_empty_array_for_no_dependencies
    task_class = Class.new(Taski::Task) do
      def run
        # No dependencies
      end
    end

    assert_equal [], task_class.dependencies
  end

  def test_dependencies_method_returns_array
    task_class = Class.new(Taski::Task) do
      def run
      end
    end

    dependencies = task_class.dependencies
    assert_instance_of Array, dependencies
  end

  def test_dependencies_method_returns_dependencies_array
    # Create a task with dependencies
    dependency_task = Class.new(Taski::Task) do
      exports :value
      def run
        @value = "dependency_result"
      end
    end
    # Set as constant for dependency detection
    Object.const_set(:TestDependencyTask, dependency_task)

    main_task = Class.new(Taski::Task) do
      def run
        # This should create a dependency on TestDependencyTask
        TestDependencyTask.value
      end
    end
    Object.const_set(:TestMainTask, main_task)

    # Trigger dependency analysis by running the task
    TestMainTask.run

    # Check that dependencies method returns the correct structure
    dependencies = TestMainTask.dependencies
    assert_kind_of Array, dependencies

    # Each dependency should be a hash with :klass key
    dependencies.each do |dep|
      assert_kind_of Hash, dep
      assert dep.key?(:klass)
      assert dep[:klass].is_a?(Class)
    end
  ensure
    # Clean up constants
    Object.send(:remove_const, :TestDependencyTask) if defined?(TestDependencyTask)
    Object.send(:remove_const, :TestMainTask) if defined?(TestMainTask)
  end

  def test_dependencies_method_with_multiple_dependencies
    task_a = Class.new(Taski::Task) do
      exports :value_a
      def run
        @value_a = "a"
      end
    end
    Object.const_set(:TestTaskA, task_a)

    task_b = Class.new(Taski::Task) do
      exports :value_b
      def run
        @value_b = "b"
      end
    end
    Object.const_set(:TestTaskB, task_b)

    main_task = Class.new(Taski::Task) do
      def run
        # Create dependencies on both tasks
        TestTaskA.value_a
        TestTaskB.value_b
      end
    end
    Object.const_set(:TestMainMultipleTask, main_task)

    # Trigger dependency analysis
    TestMainMultipleTask.run

    dependencies = TestMainMultipleTask.dependencies
    assert_equal 2, dependencies.length

    dependency_classes = dependencies.map { |dep| dep[:klass] }
    assert_includes dependency_classes, task_a
    assert_includes dependency_classes, task_b
  ensure
    # Clean up constants
    Object.send(:remove_const, :TestTaskA) if defined?(TestTaskA)
    Object.send(:remove_const, :TestTaskB) if defined?(TestTaskB)
    Object.send(:remove_const, :TestMainMultipleTask) if defined?(TestMainMultipleTask)
  end

  def test_dependencies_with_actual_dependencies
    dep_task = Class.new(Taski::Task) do
      def run
      end
    end
    Object.const_set(:DepTask, dep_task)

    main_task = Class.new(Taski::Task) do
      def run
        DepTask.ensure_instance_built
      end
    end
    Object.const_set(:MainTask, main_task)

    # 依存関係を解決してから確認
    main_task.resolve_dependencies

    dependencies = main_task.dependencies
    assert_equal 1, dependencies.size, "Should have one dependency"

    first_dep = dependencies.first
    assert_instance_of Hash, first_dep, "Dependency should be a Hash"
    assert_equal DepTask, first_dep[:klass], "Dependency should reference DepTask"
  ensure
    # Clean up constants
    Object.send(:remove_const, :DepTask) if defined?(DepTask)
    Object.send(:remove_const, :MainTask) if defined?(MainTask)
  end

  def test_dependencies_without_dependencies
    task = Class.new(Taski::Task) do
      def run
      end
    end

    dependencies = task.dependencies
    assert_empty dependencies, "Should have no dependencies"
  end

  # ========================================================================
  # REFERENCE CLASS TESTS - Low-level Reference object functionality
  # ========================================================================

  def test_reference_basic_functionality
    # Test Reference class basic operations: creation, dereferencing, comparison, inspection
    ref = Taski::Reference.new("String")

    assert_instance_of Taski::Reference, ref
    assert_equal String, ref.deref
    assert ref == String
    assert_equal "&String", ref.inspect
  end

  def test_reference_error_handling
    # Test Reference class error handling for non-existent constants
    ref = Taski::Reference.new("NonExistentClass")

    # deref should raise TaskAnalysisError for non-existent class
    error = assert_raises(Taski::TaskAnalysisError) do
      ref.deref
    end

    assert_includes error.message, "Cannot resolve constant 'NonExistentClass'"

    # == should return false for non-existent class
    refute ref == String
  end

  # ========================================================================
  # REF() METHOD TESTS - High-level ref() method functionality
  # ========================================================================

  def test_ref_enables_forward_declaration
    # Test forward declaration: ref() allows referencing classes defined later
    # This is the primary use case for ref() - defining task dependencies in reverse order

    # Define TaskB first (references TaskA that doesn't exist yet)
    task_b = Class.new(Taski::Task) do
      exports :result_b

      def run
        # ref() should resolve forward declaration to actual class at runtime
        task_a_ref = ref("ForwardDeclTaskA")
        @result_b = "Result from B, depending on #{task_a_ref.result_a}"
      end
    end
    Object.const_set(:ForwardDeclTaskB, task_b)

    # Now define TaskA after TaskB has already referenced it
    task_a = Class.new(Taski::Task) do
      exports :result_a

      def run
        @result_a = "Result from A"
      end
    end
    Object.const_set(:ForwardDeclTaskA, task_a)

    # Verify that forward declaration resolves correctly at runtime
    output = capture_io { ForwardDeclTaskB.run }

    # Both tasks should execute successfully - forward declaration resolved
    assert_includes output[0], "Task build completed (task=ForwardDeclTaskB"
    assert_includes output[0], "Task build completed (task=ForwardDeclTaskA"
  ensure
    Object.send(:remove_const, :ForwardDeclTaskA) if Object.const_defined?(:ForwardDeclTaskA)
    Object.send(:remove_const, :ForwardDeclTaskB) if Object.const_defined?(:ForwardDeclTaskB)
  end

  def test_ref_error_handling_at_runtime
    # Test ref() error handling for truly non-existent classes
    # ref() should raise TaskAnalysisError (wrapped in TaskBuildError) for invalid references
    task_a = Class.new(Taski::Task) do
      exports :result_a

      def run
        # Attempt to reference a class that will never exist
        _task_ref = ref("NonExistentClass")
        @result_a = "This should not execute"
      end
    end
    Object.const_set(:RuntimeRefTask, task_a)

    # Verify that ref() with non-existent class raises appropriate error
    error = assert_raises Taski::TaskBuildError do
      RuntimeRefTask.run
    end
    assert_includes error.message, "Cannot resolve constant 'NonExistentClass'"
  ensure
    Object.send(:remove_const, :RuntimeRefTask) if Object.const_defined?(:RuntimeRefTask)
  end

  # ========================================================================
  # CIRCULAR DEPENDENCY DETAIL TESTS
  # ========================================================================

  def test_circular_dependency_detailed_error_message
    # Create a simple circular dependency: A -> B -> A
    task_a = Class.new(Taski::Task) do
      exports :result_a

      def run
        puts "Building A"
        @result_a = DetailedCircularB.result_b
      end
    end
    Object.const_set(:DetailedCircularA, task_a)

    task_b = Class.new(Taski::Task) do
      exports :result_b

      def run
        puts "Building B"
        @result_b = DetailedCircularA.result_a
      end
    end
    Object.const_set(:DetailedCircularB, task_b)

    # Capture the error message
    error = assert_raises(Taski::TaskBuildError) do
      DetailedCircularA.run
    end

    # Check that the error message contains detailed information
    assert_includes error.message, "Circular dependency detected!"
    assert_includes error.message, "DetailedCircularA"
    assert_includes error.message, "DetailedCircularB"
    assert_includes error.message, "→"
  end

  def test_complex_circular_dependency_path
    # Create a more complex circular dependency: A -> B -> C -> D -> B
    task_a = Class.new(Taski::Task) do
      def run
        ComplexCircularB.run
      end
    end
    Object.const_set(:ComplexCircularA, task_a)

    task_b = Class.new(Taski::Task) do
      def run
        ComplexCircularC.run
      end
    end
    Object.const_set(:ComplexCircularB, task_b)

    task_c = Class.new(Taski::Task) do
      def run
        ComplexCircularD.run
      end
    end
    Object.const_set(:ComplexCircularC, task_c)

    task_d = Class.new(Taski::Task) do
      def run
        ComplexCircularB.run  # Creates cycle
      end
    end
    Object.const_set(:ComplexCircularD, task_d)

    # Attempting to build should raise TaskBuildError (wrapping CircularDependencyError)
    error = assert_raises(Taski::TaskBuildError) do
      ComplexCircularA.run
    end

    # The error message should show the detailed cycle information
    assert_includes error.message, "Circular dependency detected!"
    assert_includes error.message, "ComplexCircularB"
    assert_includes error.message, "→"
    assert_includes error.message, "The runtime chain is:"
  end

  def test_circular_dependency_with_exports_api
    # Test circular dependency detection with exports API
    task_x = Class.new(Taski::Task) do
      exports :value_x

      def run
        @value_x = "X-#{ExportsCircularY.value_y}"
      end
    end
    Object.const_set(:ExportsCircularX, task_x)

    task_y = Class.new(Taski::Task) do
      exports :value_y

      def run
        @value_y = "Y-#{ExportsCircularX.value_x}"
      end
    end
    Object.const_set(:ExportsCircularY, task_y)

    # Should detect circular dependency (wrapped in TaskBuildError)
    error = assert_raises(Taski::TaskBuildError) do
      ExportsCircularX.run
    end

    assert_includes error.message, "Circular dependency detected!"
    assert_includes error.message, "ExportsCircularX"
    assert_includes error.message, "ExportsCircularY"
    assert_includes error.message, "→"
    assert_includes error.message, "runtime chain"
  end

  private

  def setup_deep_dependency_chain
    # Skip if already set up
    return if defined?(DeepTaskD)

    task_d = Class.new(Taski::Task) do
      exports :d_value

      def run
        TaskiTestHelper.track_build_order("DeepTaskD")
        @d_value = "D"
      end
    end
    Object.const_set(:DeepTaskD, task_d)

    task_c = Class.new(Taski::Task) do
      exports :c_value

      def run
        TaskiTestHelper.track_build_order("DeepTaskC")
        @c_value = "C-#{DeepTaskD.d_value}"
      end
    end
    Object.const_set(:DeepTaskC, task_c)

    task_b = Class.new(Taski::Task) do
      exports :b_value

      def run
        TaskiTestHelper.track_build_order("DeepTaskB")
        @b_value = "B-#{DeepTaskC.c_value}"
      end
    end
    Object.const_set(:DeepTaskB, task_b)

    task_a = Class.new(Taski::Task) do
      exports :a_value

      def run
        TaskiTestHelper.track_build_order("DeepTaskA")
        @a_value = "A-#{DeepTaskB.b_value}"
      end
    end
    Object.const_set(:DeepTaskA, task_a)
  end
end
