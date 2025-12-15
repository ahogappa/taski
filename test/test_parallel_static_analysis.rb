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
end
