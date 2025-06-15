# frozen_string_literal: true

require_relative "test_helper"

class TestStaticAnalysis < Minitest::Test
  include TaskiTestHelper

  def setup
    setup_taski_test
  end

  # === Static Analysis Tests ===

  def test_static_analysis_with_exports
    # Test static analysis detection of dependencies in build methods
    task_a = Class.new(Taski::Task) do
      exports :task_a_result

      def build
        TaskiTestHelper.track_build_order("StaticTaskA")
        @task_a_result = "Task A"
        puts 'StaticTaskA Processing...'
      end

      def clean
        puts 'StaticTaskA Cleaning...'
      end
    end
    Object.const_set(:StaticTaskA, task_a)

    task_b = Class.new(Taski::Task) do
      def build
        TaskiTestHelper.track_build_order("StaticTaskB")
        puts "Task result is #{StaticTaskA.task_a_result}"
      end

      def clean
        puts 'StaticTaskB Cleaning...'
      end
    end
    Object.const_set(:StaticTaskB, task_b)

    # Verify static analysis detected the dependency
    dependencies = StaticTaskB.instance_variable_get(:@dependencies) || []
    dependency_classes = dependencies.map { |d| d[:klass] }
    assert_includes dependency_classes, StaticTaskA, "Static analysis should detect StaticTaskA dependency"

    # Reset and build
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

    # Verify dependency was detected
    dependencies = NestedTaskB.instance_variable_get(:@dependencies) || []
    dependency_classes = dependencies.map { |d| d[:klass] }
    assert_includes dependency_classes, TestModule::NestedTaskA
  end

  def test_dependency_analyzer_error_handling
    # Test DependencyAnalyzer with invalid file
    dependencies = Taski::DependencyAnalyzer.analyze_method(String, :build)
    assert_equal [], dependencies
  end

  def test_deep_dependency_chain
    # Test a deep dependency chain (A -> B -> C -> D)
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

    # Reset and build
    TaskiTestHelper.reset_build_order
    DeepTaskA.build

    # Verify build order (D should be built first, A last)
    build_order = TaskiTestHelper.build_order
    assert_equal "DeepTaskD", build_order.first
    assert_equal "DeepTaskA", build_order.last
    
    # Verify final values
    assert_equal "D", DeepTaskD.d_value
    assert_equal "C-D", DeepTaskC.c_value
    assert_equal "B-C-D", DeepTaskB.b_value
    assert_equal "A-B-C-D", DeepTaskA.a_value
  end
end