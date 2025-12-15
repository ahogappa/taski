# frozen_string_literal: true

require "test_helper"
require_relative "fixtures/parallel_tasks"

class TestTreeDisplay < Minitest::Test
  # Remove ANSI color codes for testing
  def strip_ansi(str)
    str.gsub(/\e\[[0-9;]*m/, "")
  end

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

  def test_tree_shows_type_label_for_task
    result = FixtureTaskA.tree
    assert_includes result, "(Task)"
  end

  def test_tree_shows_type_label_for_section
    result = NestedSection.tree
    assert_includes result, "(Section)"
  end

  def test_tree_shows_impl_prefix_for_section_dependency
    result = NestedSection.tree
    assert_includes result, "[impl]"
    assert_includes result, "NestedSection::LocalDB"
  end

  def test_tree_shows_nested_section_with_impl
    result = strip_ansi(OuterSection.tree)
    assert_includes result, "OuterSection (Section)"
    assert_includes result, "[impl]"
    assert_includes result, "InnerSection (Section)"
    assert_includes result, "InnerSection::InnerImpl (Task)"
  end

  def test_tree_shows_mixed_task_and_section_dependencies
    result = strip_ansi(DeepDependency::TaskD.tree)
    assert_includes result, "DeepDependency::TaskD (Task)"
    assert_includes result, "ParallelTaskC (Task)"
    assert_includes result, "ParallelSection (Section)"
    assert_includes result, "[impl]"
    assert_includes result, "ParallelSectionImpl2 (Task)"
  end

  def test_tree_includes_ansi_color_codes
    result = FixtureTaskA.tree
    # Check that ANSI codes are present
    assert_match(/\e\[/, result)
  end
end
