# frozen_string_literal: true

require "test_helper"
require_relative "fixtures/parallel_tasks"

class TestTreeDisplay < Minitest::Test
  def test_tree_method_exists
    assert_respond_to FixtureTaskA, :tree
  end

  def test_tree_returns_string
    result = FixtureTaskA.tree
    assert_kind_of String, result
  end

  def test_tree_includes_task_name
    result = FixtureTaskA.tree
    assert_includes result, "FixtureTaskA"
  end

  def test_tree_shows_simple_dependency
    result = FixtureTaskB.tree
    assert_includes result, "FixtureTaskB"
    assert_includes result, "FixtureTaskA"
  end

  def test_tree_shows_nested_dependencies
    result = FixtureNamespace::TaskD.tree
    assert_includes result, "FixtureNamespace::TaskD"
    assert_includes result, "FixtureNamespace::TaskC"
    assert_includes result, "FixtureTaskA"
  end

  def test_tree_shows_deep_dependencies
    result = DeepDependency::Nested::TaskH.tree
    assert_includes result, "DeepDependency::Nested::TaskH"
    assert_includes result, "DeepDependency::Nested::TaskG"
    assert_includes result, "DeepDependency::TaskE"
    assert_includes result, "DeepDependency::TaskF"
    assert_includes result, "DeepDependency::TaskD"
    assert_includes result, "ParallelTaskC"
  end
end
