# frozen_string_literal: true

require "test_helper"
require_relative "fixtures/parallel_tasks"

class TestParallelStaticAnalysis < Minitest::Test
  def test_analyze_simple_dependency
    dependencies = Taski::StaticAnalysis::Analyzer.analyze(FixtureTaskB)
    assert_includes dependencies.map(&:name), "FixtureTaskA"
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

  def test_analyze_follows_method_call_in_section_impl
    dependencies = Taski::StaticAnalysis::Analyzer.analyze(MethodCallSection)
    assert_includes dependencies.map(&:name), "MethodCallSectionImpl"
  end

  # Test for namespace resolution in helper methods
  # When a helper method uses a relative constant, it should be resolved
  # using the target class's namespace context
  def test_analyze_follows_method_call_with_relative_constant_in_namespace
    dependencies = Taski::StaticAnalysis::Analyzer.analyze(NamespacedHelper::HelperTask)
    assert_includes dependencies.map(&:name), "NamespacedHelper::DependencyTask"
  end
end
