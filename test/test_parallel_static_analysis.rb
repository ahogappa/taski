# frozen_string_literal: true

require "test_helper"
require_relative "fixtures/parallel_tasks"
require_relative "fixtures/compact_path_tasks"

class TestParallelStaticAnalysis < Minitest::Test
  def test_analyze_simple_dependency
    dependencies = Taski::StaticAnalysis::Analyzer.analyze(FixtureTaskB)
    assert_includes dependencies.map(&:name), "FixtureTaskA"
  end

  # A class defined with a compact path (class Outer::Consumer) must resolve a
  # sibling dependency referenced unqualified inside run relative to the Outer
  # namespace. Previously the compact name was pushed unsplit, so the namespace
  # prefix candidates skipped "Outer::Dep" and the dependency was dropped.
  def test_analyze_compact_path_class_resolves_sibling_dependency
    dependencies = Taski::StaticAnalysis::Analyzer.analyze(CompactPath::Consumer)
    assert_includes dependencies, CompactPath::Dep
  end

  def test_analyze_namespaced_dependency
    dependencies = Taski::StaticAnalysis::Analyzer.analyze(FixtureNamespace::TaskC)
    assert_includes dependencies.map(&:name), "FixtureTaskA"
  end

  def test_analyze_relative_namespaced_dependency
    dependencies = Taski::StaticAnalysis::Analyzer.analyze(FixtureNamespace::TaskD)
    assert_includes dependencies.map(&:name), "FixtureNamespace::TaskC"
  end

  def test_analyze_task_without_dependencies
    dependencies = Taski::StaticAnalysis::Analyzer.analyze(FixtureTaskA)
    assert_empty dependencies
  end

  # Tests for following method calls from run/impl
  def test_analyze_follows_method_call_from_run
    dependencies = Taski::StaticAnalysis::Analyzer.analyze(MethodCallFollowTask)
    assert_includes dependencies.map(&:name), "MethodCallBaseTask"
  end

  def test_analyze_follows_nested_method_calls
    dependencies = Taski::StaticAnalysis::Analyzer.analyze(NestedMethodCallTask)
    assert_includes dependencies.map(&:name), "MethodCallBaseTask"
  end

  def test_analyze_follows_multiple_method_calls
    dependencies = Taski::StaticAnalysis::Analyzer.analyze(MultiMethodTask)
    dep_names = dependencies.map(&:name)
    assert_includes dep_names, "MethodCallBaseTask"
    assert_includes dep_names, "MethodCallFollowTask"
  end

  # Test for namespace resolution in helper methods
  # When a helper method uses a relative constant, it should be resolved
  # using the target class's namespace context
  def test_analyze_follows_method_call_with_relative_constant_in_namespace
    dependencies = Taski::StaticAnalysis::Analyzer.analyze(NamespacedHelper::HelperTask)
    assert_includes dependencies.map(&:name), "NamespacedHelper::DependencyTask"
  end
end
