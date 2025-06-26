# frozen_string_literal: true

require_relative "test_helper"

class TestErrorHandling < Minitest::Test
  include TaskiTestHelper

  def setup
    setup_taski_test
  end

  # === Error Handling Tests ===

  def test_build_error_handling
    # Test error handling during build
    task = Class.new(Taski::Task) do
      def build
        raise StandardError, "Build failed intentionally"
      end
    end
    Object.const_set(:ErrorTaskA, task)

    # Building should raise TaskBuildError
    error = assert_raises(Taski::TaskBuildError) do
      ErrorTaskA.build
    end

    assert_includes error.message, "Failed to build task ErrorTaskA"
    assert_includes error.message, "Build failed intentionally"
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
    assert_equal false, (ref == String)
  end

  def test_task_analysis_error
    # Test TaskAnalysisError is properly defined
    error = Taski::TaskAnalysisError.new("test message")
    assert_instance_of Taski::TaskAnalysisError, error
    assert_kind_of StandardError, error
    assert_equal "test message", error.message
  end

  def test_circular_dependency_error
    # Test CircularDependencyError is properly defined
    error = Taski::CircularDependencyError.new("circular dependency")
    assert_instance_of Taski::CircularDependencyError, error
    assert_kind_of StandardError, error
    assert_equal "circular dependency", error.message
  end

  def test_task_build_error
    # Test TaskBuildError is properly defined
    error = Taski::TaskBuildError.new("build error")
    assert_instance_of Taski::TaskBuildError, error
    assert_kind_of StandardError, error
    assert_equal "build error", error.message
  end

  def test_build_dependencies_error_resilience
    # Test that build continues even if one dependency fails
    failing_task = Class.new(Taski::Task) do
      def build
        raise StandardError, "Intentional failure"
      end
    end
    Object.const_set(:FailingTask, failing_task)

    dependent_task = Class.new(Taski::Task) do
      # Manually add dependency that will fail
      @dependencies = [{klass: FailingTask}]

      def build
        puts "This should not be reached"
      end
    end
    Object.const_set(:DependentTask, dependent_task)

    # Should raise TaskBuildError due to failing dependency
    assert_raises(Taski::TaskBuildError) do
      DependentTask.build
    end
  end

  def test_not_implemented_error
    # Test that base Task class raises NotImplementedError for build
    task = Taski::Task.new

    error = assert_raises(NotImplementedError) do
      task.build
    end

    assert_includes error.message, "You must implement the build method"
  end
end
