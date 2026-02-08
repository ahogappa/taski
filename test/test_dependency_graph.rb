# frozen_string_literal: true

require "test_helper"

class TestDependencyGraphBuildFromCached < Minitest::Test
  def setup
    Taski::Task.reset! if defined?(Taski::Task)
  end

  def test_build_from_cached_single_task
    task = Class.new(Taski::Task) do
      exports :value
      def run
        @value = "test"
      end
    end

    graph = Taski::StaticAnalysis::DependencyGraph.new
    graph.build_from_cached(task)

    assert_includes graph.all_tasks, task
    assert_empty graph.dependencies_for(task)
  end

  def test_build_from_cached_with_dependencies
    task_a = Class.new(Taski::Task) do
      exports :value
      def run
        @value = "a"
      end
    end
    task_a.define_singleton_method(:cached_dependencies) { Set.new }

    task_b = Class.new(Taski::Task) do
      exports :value
      def run
        @value = "b"
      end
    end
    task_b.define_singleton_method(:cached_dependencies) { Set[task_a] }

    task_c = Class.new(Taski::Task) do
      exports :value
      def run
        @value = "c"
      end
    end
    task_c.define_singleton_method(:cached_dependencies) { Set[task_a, task_b] }

    graph = Taski::StaticAnalysis::DependencyGraph.new
    graph.build_from_cached(task_c)

    assert_includes graph.all_tasks, task_a
    assert_includes graph.all_tasks, task_b
    assert_includes graph.all_tasks, task_c
    assert_equal Set[task_a, task_b], graph.dependencies_for(task_c)
    assert_equal Set[task_a], graph.dependencies_for(task_b)
    assert_empty graph.dependencies_for(task_a)
  end

  def test_build_from_cached_returns_self
    task = Class.new(Taski::Task) do
      exports :value
      def run
        @value = "test"
      end
    end

    graph = Taski::StaticAnalysis::DependencyGraph.new
    result = graph.build_from_cached(task)

    assert_same graph, result
  end
end
