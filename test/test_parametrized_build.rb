# frozen_string_literal: true

require_relative "test_helper"

class TestParametrizedBuild < Minitest::Test
  def setup
    # Each test will create isolated task classes
    # No global state manipulation needed
  end

  def teardown
    # Tasks created in tests are isolated and don't need cleanup
  end

  # Basic parametrized build functionality
  def test_build_without_args_returns_instance
    task_class = Class.new(Taski::Task) do
      def self.name
        "TestTask"
      end

      def build
        @result = "default"
      end
    end

    result = task_class.build
    assert_instance_of task_class, result
    assert_equal "default", result.instance_variable_get(:@result)
  end

  def test_build_with_args_returns_different_instance
    task_class = Class.new(Taski::Task) do
      def self.name
        "TestTask"
      end

      def build
        args = build_args
        @result = args[:mode] || "default"
      end
    end

    # Build without args - returns singleton instance
    singleton_instance = task_class.build
    assert_instance_of task_class, singleton_instance
    assert_equal "default", singleton_instance.instance_variable_get(:@result)

    # Build with args - returns different temporary instance
    temp_instance = task_class.build(mode: "fast")
    assert_instance_of task_class, temp_instance
    assert_equal "fast", temp_instance.instance_variable_get(:@result)

    # Should be different instances
    refute_equal singleton_instance, temp_instance
  end

  def test_build_args_accessible_in_instance_build
    task_class = Class.new(Taski::Task) do
      def self.name
        "TestTask"
      end

      def build
        args = build_args
        @mode = args[:mode]
        @input = args[:input]
        @result = "processed_#{@mode}_#{@input}"
      end
    end

    instance = task_class.build(mode: "thorough", input: "data")
    assert_equal "thorough", instance.instance_variable_get(:@mode)
    assert_equal "data", instance.instance_variable_get(:@input)
    assert_equal "processed_thorough_data", instance.instance_variable_get(:@result)
  end

  def test_build_args_empty_for_no_args_build
    task_class = Class.new(Taski::Task) do
      def self.name
        "TestTask"
      end

      def build
        @args_size = build_args.size
      end
    end

    # Build without args - instance uses singleton pattern
    task_class.build
    singleton_instance = task_class.instance_variable_get(:@__task_instance)
    assert_equal 0, singleton_instance.instance_variable_get(:@args_size)
  end

  # Dependencies with parametrized builds
  def test_dependencies_resolved_with_parametrized_build
    base_task = Class.new(Taski::Task) do
      exports :base_result

      def self.name
        "ParametrizedBaseTask"
      end

      def build
        @base_result = "base_built"
      end
    end
    Object.const_set(:ParametrizedBaseTask, base_task)

    dependent_task = Class.new(Taski::Task) do
      exports :dependent_result

      def self.name
        "ParametrizedDependentTask"
      end

      def build
        # Create natural dependency by accessing ParametrizedBaseTask
        ParametrizedBaseTask.base_result  # This creates the dependency
        args = build_args
        @dependent_result = "dependent_built_#{args[:option] || "default"}"
      end
    end
    Object.const_set(:ParametrizedDependentTask, dependent_task)

    instance = dependent_task.build(option: "value")

    # Base task should have been built through dependency resolution
    assert_equal "base_built", ParametrizedBaseTask.base_result
    assert_equal "dependent_built_value", instance.dependent_result
  end

  # Multiple parametrized builds don't interfere
  def test_multiple_parametrized_builds_independent
    task_class = Class.new(Taski::Task) do
      def self.name
        "TestTask"
      end

      def build
        args = build_args
        @result = "result_#{args[:id]}"
      end
    end

    instance1 = task_class.build(id: "first")
    instance2 = task_class.build(id: "second")

    assert_equal "result_first", instance1.instance_variable_get(:@result)
    assert_equal "result_second", instance2.instance_variable_get(:@result)
    refute_equal instance1, instance2
  end

  # Backward compatibility (return value changed but functionality preserved)
  def test_singleton_behavior_preserved
    task_class = Class.new(Taski::Task) do
      def self.name
        "TestTask"
      end

      def build
        @result = "original_behavior"
      end
    end

    # Build returns instance now instead of class
    result = task_class.build
    assert_instance_of task_class, result
    assert_equal "original_behavior", result.instance_variable_get(:@result)

    # Singleton instance should be created and same as returned instance
    singleton_instance = task_class.instance_variable_get(:@__task_instance)
    refute_nil singleton_instance
    assert_equal result, singleton_instance
    assert_equal "original_behavior", singleton_instance.instance_variable_get(:@result)
  end

  # Error handling
  def test_error_in_parametrized_build_includes_args
    task_class = Class.new(Taski::Task) do
      def self.name
        "FailingTask"
      end

      def build
        # Check if this is a parametrized build
        if build_args.any?
          raise StandardError, "parametrized build failed"
        else
          @result = "success"
        end
      end
    end

    # First ensure normal build works
    normal_instance = task_class.build
    assert_equal "success", normal_instance.instance_variable_get(:@result)

    # Now test parametrized build failure
    error = assert_raises(Taski::TaskBuildError) do
      task_class.build(mode: "test")
    end

    assert_includes error.message, "FailingTask"
    assert_includes error.message, '{mode: "test"}'
  end

  private

  # No cleanup methods needed - tests use isolated task classes
end
