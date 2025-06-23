# frozen_string_literal: true

require_relative "test_helper"

class TestCircularDependencyDetail < Minitest::Test
  include TaskiTestHelper

  def setup
    setup_taski_test
  end

  def test_circular_dependency_detailed_error_message
    # Create a simple circular dependency: A -> B -> A
    task_a = Class.new(Taski::Task) do
      @dependencies = [{klass: proc { DetailedCircularB }}]

      def build
        puts "Building A"
      end
    end
    Object.const_set(:DetailedCircularA, task_a)

    task_b = Class.new(Taski::Task) do
      @dependencies = [{klass: proc { DetailedCircularA }}]

      def build
        puts "Building B"
      end
    end
    Object.const_set(:DetailedCircularB, task_b)

    # Replace procs with actual references
    DetailedCircularA.instance_variable_set(:@dependencies, [{klass: DetailedCircularB}])
    DetailedCircularB.instance_variable_set(:@dependencies, [{klass: DetailedCircularA}])

    # Capture the error message
    error = assert_raises(Taski::CircularDependencyError) do
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
end
