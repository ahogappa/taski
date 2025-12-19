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

  # Section.impl candidates ARE shown in tree display for visualization purposes
  # even though they are resolved at runtime for execution
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
    # ParallelSectionImpl2 is not a nested class of ParallelSection,
    # so it should NOT have [impl] label (only nested classes get [impl])
    assert_includes result, "ParallelSectionImpl2 (Task)"
    refute_includes result, "[impl] ParallelSectionImpl2"
  end

  def test_tree_includes_ansi_color_codes
    result = FixtureTaskA.tree
    # Check that ANSI codes are present
    assert_match(/\e\[/, result)
  end

  def test_tree_shows_task_numbers
    result = strip_ansi(FixtureTaskB.tree)
    assert_match(/\[1\].*FixtureTaskB/, result)
    assert_match(/\[2\].*FixtureTaskA/, result)
  end

  def test_tree_same_task_has_same_number
    result = strip_ansi(DeepDependency::Nested::TaskH.tree)
    # Find all occurrences of ParallelTaskA with their numbers
    matches = result.scan(/\[(\d+)\].*ParallelTaskA/)
    assert matches.size >= 2, "ParallelTaskA should appear multiple times"
    # All occurrences should have the same number
    numbers = matches.flatten.uniq
    assert_equal 1, numbers.size, "Same task should have the same number"
  end

  def test_tree_expands_duplicate_dependencies
    result = strip_ansi(DeepDependency::Nested::TaskH.tree)
    # ParallelSection appears multiple times and should be fully expanded each time
    # Count how many times ParallelSectionImpl2 appears (it's a dependency of ParallelSection)
    impl_count = result.scan("ParallelSectionImpl2").size
    assert impl_count >= 2, "ParallelSectionImpl2 should appear multiple times as ParallelSection is fully expanded"
  end

  def test_tree_shows_circular_marker_for_circular_dependency
    require_relative "fixtures/circular_tasks"
    result = strip_ansi(CircularTaskA.tree)
    assert_includes result, "CircularTaskA"
    assert_includes result, "CircularTaskB"
    assert_includes result, "(circular)"
  end

  def test_tree_shows_circular_marker_for_indirect_circular_dependency
    require_relative "fixtures/circular_tasks"
    result = strip_ansi(IndirectCircular::TaskX.tree)
    assert_includes result, "IndirectCircular::TaskX"
    assert_includes result, "IndirectCircular::TaskY"
    assert_includes result, "IndirectCircular::TaskZ"
    assert_includes result, "(circular)"
  end
end
