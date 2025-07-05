require_relative "test_helper"

class TestDependenciesMethod < Minitest::Test
  include TaskiTestHelper

  def setup
    setup_taski_test
  end

  def test_dependencies_method_returns_empty_array_for_no_dependencies
    task_class = Class.new(Taski::Task) do
      def run
        # No dependencies
      end
    end

    assert_equal [], task_class.dependencies
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

  def test_dependencies_method_consistency_with_internal_implementation
    # Test that dependencies method returns the same as internal @dependencies
    task_class = Class.new(Taski::Task) do
      def run
        # Empty for now
      end
    end

    # Access internal implementation for comparison
    internal_deps = task_class.instance_variable_get(:@dependencies) || []
    public_deps = task_class.dependencies

    assert_equal internal_deps, public_deps
  end
end
