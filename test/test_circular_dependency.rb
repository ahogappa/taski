# frozen_string_literal: true

require "test_helper"
require_relative "fixtures/parallel_tasks"

class TestCircularDependency < Minitest::Test
  def setup
    Taski::Task.reset!
  end

  def teardown
    Taski::Task.reset!
  end

  def test_no_circular_dependency_executes_normally
    # FixtureTaskB depends on FixtureTaskA - no cycle
    assert_equal "B depends on A", FixtureTaskB.value_b
  end

  def test_detects_direct_circular_dependency
    require_relative "fixtures/circular_tasks"

    error = assert_raises(Taski::CircularDependencyError) do
      CircularTaskA.value
    end

    assert_includes error.message, "Circular dependency detected"
    assert_includes error.message, "CircularTaskA"
    assert_includes error.message, "CircularTaskB"
  end

  def test_detects_indirect_circular_dependency
    require_relative "fixtures/circular_tasks"

    error = assert_raises(Taski::CircularDependencyError) do
      IndirectCircular::TaskX.value
    end

    assert_includes error.message, "Circular dependency detected"
    # All three tasks should be in the cycle
    assert_includes error.message, "TaskX"
    assert_includes error.message, "TaskY"
    assert_includes error.message, "TaskZ"
  end

  def test_circular_dependency_error_message_format
    task_a = Class.new(Taski::Task) { def self.name = "ErrorTestA" }
    task_b = Class.new(Taski::Task) { def self.name = "ErrorTestB" }

    error = Taski::CircularDependencyError.new([[task_a, task_b]])
    assert_includes error.message, "Circular dependency detected"
    assert_includes error.message, "ErrorTestA"
    assert_includes error.message, "ErrorTestB"
    assert_includes error.message, "<->"
    assert_equal [[task_a, task_b]], error.cyclic_tasks
  end

  def test_dependency_graph_build_from_task
    # FixtureTaskB depends on FixtureTaskA
    graph = Taski::StaticAnalysis::DependencyGraph.new.build_from(FixtureTaskB)

    assert_equal 2, graph.all_tasks.size
    assert_includes graph.all_tasks, FixtureTaskA
    assert_includes graph.all_tasks, FixtureTaskB
    refute graph.cyclic?
  end

  def test_dependency_graph_topological_sort
    # SequentialTaskD -> C -> B -> A
    graph = Taski::StaticAnalysis::DependencyGraph.new.build_from(SequentialTaskD)

    sorted = graph.sorted
    assert_equal 4, sorted.size
    # A should come before B, B before C, C before D
    assert sorted.index(SequentialTaskA) < sorted.index(SequentialTaskB)
    assert sorted.index(SequentialTaskB) < sorted.index(SequentialTaskC)
    assert sorted.index(SequentialTaskC) < sorted.index(SequentialTaskD)
  end

  def test_no_cycle_returns_empty_cyclic_components
    graph = Taski::StaticAnalysis::DependencyGraph.new.build_from(FixtureTaskB)

    assert_empty graph.cyclic_components
  end

  def test_dependencies_for_returns_direct_dependencies
    graph = Taski::StaticAnalysis::DependencyGraph.new.build_from(FixtureTaskB)

    deps = graph.dependencies_for(FixtureTaskB)
    assert_includes deps, FixtureTaskA

    deps_a = graph.dependencies_for(FixtureTaskA)
    assert_empty deps_a
  end

  def test_circular_dependency_detected_on_run
    require_relative "fixtures/circular_tasks"

    assert_raises(Taski::CircularDependencyError) do
      CircularTaskA.run
    end
  end

  def test_circular_dependency_detected_on_clean
    require_relative "fixtures/circular_tasks"

    assert_raises(Taski::CircularDependencyError) do
      CircularTaskA.clean
    end
  end

  def test_deep_dependency_chain_without_cycle
    # DeepDependency::Nested::TaskH has a deep dependency chain
    graph = Taski::StaticAnalysis::DependencyGraph.new.build_from(DeepDependency::Nested::TaskH)

    refute graph.cyclic?
    assert graph.all_tasks.size > 5
  end
end
