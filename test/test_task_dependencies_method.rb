# frozen_string_literal: true

require_relative "test_helper"

class TestTaskDependenciesMethod < Minitest::Test
  include TaskiTestHelper

  def setup
    setup_taski_test
  end

  def test_task_has_dependencies_method
    task = Class.new(Taski::Task) do
      def run
      end
    end

    assert_respond_to task, :dependencies, "Task class should have dependencies method"
  end

  def test_dependencies_returns_array
    task = Class.new(Taski::Task) do
      def run
      end
    end

    dependencies = task.dependencies
    assert_instance_of Array, dependencies, "dependencies should return an Array"
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
  end

  def test_dependencies_without_dependencies
    task = Class.new(Taski::Task) do
      def run
      end
    end

    dependencies = task.dependencies
    assert_empty dependencies, "Should have no dependencies"
  end
end
