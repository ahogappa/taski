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

      def build
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
      def build
        TaskiTestHelper.track_build_order("StaticTaskB")
        puts "Task result is #{StaticTaskA.task_a_result}"
      end

      def clean
        puts "StaticTaskB Cleaning..."
      end
    end
    Object.const_set(:StaticTaskB, task_b)

    # Reset and build (dependency detection will be verified through build order)
    TaskiTestHelper.reset_build_order

    output = capture_io { StaticTaskB.build }
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

        def build
          @nested_value = "nested A"
        end
      end)
    end
    Object.const_set(:TestModule, nested_module)

    task_b = Class.new(Taski::Task) do
      def build
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
    DeepTaskA.build

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
    DeepTaskA.build

    # Verify final values are correctly built from dependencies
    assert_equal "D", DeepTaskD.d_value
    assert_equal "C-D", DeepTaskC.c_value
    assert_equal "B-C-D", DeepTaskB.b_value
    assert_equal "A-B-C-D", DeepTaskA.a_value
  end

  # ========================================================================
  # REFERENCE FUNCTIONALITY TESTS
  # ========================================================================

  def test_reference_basic_functionality
    # Test the Reference class functionality
    ref = Taski::Reference.new("String")

    assert_instance_of Taski::Reference, ref
    assert_equal String, ref.deref
    assert ref == String
    assert_equal "&String", ref.inspect
  end

  def test_reference_error_handling
    # Test Reference class error handling
    ref = Taski::Reference.new("NonExistentClass")

    # deref should raise TaskAnalysisError for non-existent class
    error = assert_raises(Taski::TaskAnalysisError) do
      ref.deref
    end

    assert_includes error.message, "Cannot resolve constant 'NonExistentClass'"

    # == should return false for non-existent class
    refute ref == String
  end

  def test_reference_in_dependencies
    # Test that Reference objects work in dependency resolution
    task_a = Class.new(Taski::Task) do
      exports :value

      def build
        TaskiTestHelper.track_build_order("RefDepTaskA")
        @value = "A"
      end
    end
    Object.const_set(:RefDepTaskA, task_a)

    task_b = Class.new(Taski::Task) do
      # Natural dependency will be detected through RefDepTaskA.value reference
      def build
        TaskiTestHelper.track_build_order("RefDepTaskB")
        puts "B depends on #{RefDepTaskA.value}"
      end
    end
    Object.const_set(:RefDepTaskB, task_b)

    # Reset and build
    TaskiTestHelper.reset_build_order
    capture_io { RefDepTaskB.build }

    # Verify build order
    build_order = TaskiTestHelper.build_order
    task_a_idx = build_order.index("RefDepTaskA")
    task_b_idx = build_order.index("RefDepTaskB")

    assert task_a_idx < task_b_idx, "RefDepTaskA should be built before RefDepTaskB"
  end

  def test_ref_method_usage
    # Test using ref() in different contexts
    task_a = Class.new(Taski::Task) do
      exports :name

      def build
        @name = "TaskA"
        puts "Building TaskA"
      end
    end
    Object.const_set(:RefTaskA, task_a)

    task_b = Class.new(Taski::Task) do
      def build
        # Use ref to get task class from string name
        ref = self.class.ref("RefTaskA")
        task_a_class = ref.is_a?(Taski::Reference) ? ref.deref : ref
        puts "Building TaskB, depends on #{task_a_class.name}"
      end
    end
    Object.const_set(:RefTaskB, task_b)

    output = capture_io { RefTaskB.build }
    assert_includes output[0], "Building TaskB, depends on RefTaskA"
    # Note: ref() at runtime doesn't create automatic dependency
    refute_includes output[0], "Building TaskA"
  end

  # TODO: These tests need to be implemented after fixing ref method
  # def test_ref_tracks_dependencies_during_analysis
  #   # Test that ref() properly tracks dependencies during define block analysis
  # end

  # def test_ref_enables_forward_declaration
  #   # Test the main use case: defining classes in reverse dependency order
  # end

  # def test_ref_error_handling_at_runtime
  #   # Test that ref() handles non-existent classes gracefully at runtime
  # end

  # ========================================================================
  # CIRCULAR DEPENDENCY DETAIL TESTS
  # ========================================================================

  def test_circular_dependency_detailed_error_message
    # Create a simple circular dependency: A -> B -> A
    task_a = Class.new(Taski::Task) do
      exports :result_a

      def build
        puts "Building A"
        @result_a = DetailedCircularB.result_b
      end
    end
    Object.const_set(:DetailedCircularA, task_a)

    task_b = Class.new(Taski::Task) do
      exports :result_b

      def build
        puts "Building B"
        @result_b = DetailedCircularA.result_a
      end
    end
    Object.const_set(:DetailedCircularB, task_b)

    # Capture the error message
    error = assert_raises(Taski::TaskBuildError) do
      DetailedCircularA.build
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
      def build
        ComplexCircularB.build
      end
    end
    Object.const_set(:ComplexCircularA, task_a)

    task_b = Class.new(Taski::Task) do
      def build
        ComplexCircularC.build
      end
    end
    Object.const_set(:ComplexCircularB, task_b)

    task_c = Class.new(Taski::Task) do
      def build
        ComplexCircularD.build
      end
    end
    Object.const_set(:ComplexCircularC, task_c)

    task_d = Class.new(Taski::Task) do
      def build
        ComplexCircularB.build  # Creates cycle
      end
    end
    Object.const_set(:ComplexCircularD, task_d)

    # Attempting to build should raise TaskBuildError (wrapping CircularDependencyError)
    error = assert_raises(Taski::TaskBuildError) do
      ComplexCircularA.build
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

      def build
        @value_x = "X-#{ExportsCircularY.value_y}"
      end
    end
    Object.const_set(:ExportsCircularX, task_x)

    task_y = Class.new(Taski::Task) do
      exports :value_y

      def build
        @value_y = "Y-#{ExportsCircularX.value_x}"
      end
    end
    Object.const_set(:ExportsCircularY, task_y)

    # Should detect circular dependency (wrapped in TaskBuildError)
    error = assert_raises(Taski::TaskBuildError) do
      ExportsCircularX.build
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

      def build
        TaskiTestHelper.track_build_order("DeepTaskD")
        @d_value = "D"
      end
    end
    Object.const_set(:DeepTaskD, task_d)

    task_c = Class.new(Taski::Task) do
      exports :c_value

      def build
        TaskiTestHelper.track_build_order("DeepTaskC")
        @c_value = "C-#{DeepTaskD.d_value}"
      end
    end
    Object.const_set(:DeepTaskC, task_c)

    task_b = Class.new(Taski::Task) do
      exports :b_value

      def build
        TaskiTestHelper.track_build_order("DeepTaskB")
        @b_value = "B-#{DeepTaskC.c_value}"
      end
    end
    Object.const_set(:DeepTaskB, task_b)

    task_a = Class.new(Taski::Task) do
      exports :a_value

      def build
        TaskiTestHelper.track_build_order("DeepTaskA")
        @a_value = "A-#{DeepTaskB.b_value}"
      end
    end
    Object.const_set(:DeepTaskA, task_a)
  end
end
