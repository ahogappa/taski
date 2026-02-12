# frozen_string_literal: true

require "test_helper"
require_relative "fixtures/start_dep_analyzer_tasks"

class TestStartDepAnalyzer < Minitest::Test
  def setup
    Taski::StaticAnalysis::StartDepAnalyzer.clear_cache!
  end

  def test_local_variable_assignment_dep
    result = Taski::StaticAnalysis::StartDepAnalyzer.analyze(
      StartDepAnalyzerFixtures::LocalVarAssignment
    )

    assert_equal 1, result.size
    assert_equal StartDepAnalyzerFixtures::LeafTask, result.first.klass
  end

  def test_instance_variable_assignment_dep
    result = Taski::StaticAnalysis::StartDepAnalyzer.analyze(
      StartDepAnalyzerFixtures::IvarAssignment
    )

    assert_equal 1, result.size
    assert_equal StartDepAnalyzerFixtures::LeafTask, result.first.klass
  end

  def test_multiple_assignment_deps
    result = Taski::StaticAnalysis::StartDepAnalyzer.analyze(
      StartDepAnalyzerFixtures::MultipleAssignments
    )

    classes = result.map(&:klass)
    assert_equal 2, result.size
    assert_includes classes, StartDepAnalyzerFixtures::LeafTask
    assert_includes classes, StartDepAnalyzerFixtures::LeafTaskB
  end

  def test_same_class_deduplicated
    result = Taski::StaticAnalysis::StartDepAnalyzer.analyze(
      StartDepAnalyzerFixtures::DedupAssignment
    )

    assert_equal 1, result.size
    assert_equal StartDepAnalyzerFixtures::LeafTask, result.first.klass
  end

  def test_non_dep_assignment_continues_scanning
    result = Taski::StaticAnalysis::StartDepAnalyzer.analyze(
      StartDepAnalyzerFixtures::NonDepAssignment
    )

    assert_equal 1, result.size
    assert_equal StartDepAnalyzerFixtures::LeafTask, result.first.klass
  end

  def test_unknown_pattern_stops_scanning
    result = Taski::StaticAnalysis::StartDepAnalyzer.analyze(
      StartDepAnalyzerFixtures::UnknownPatternStops
    )

    # if statement stops scanning, only LeafTask (before if) is returned
    assert_equal 1, result.size
    assert_equal StartDepAnalyzerFixtures::LeafTask, result.first.klass
  end

  def test_caching
    result1 = Taski::StaticAnalysis::StartDepAnalyzer.analyze(
      StartDepAnalyzerFixtures::IvarAssignment
    )
    result2 = Taski::StaticAnalysis::StartDepAnalyzer.analyze(
      StartDepAnalyzerFixtures::IvarAssignment
    )

    assert_same result1, result2
  end

  def test_namespaced_constant
    result = Taski::StaticAnalysis::StartDepAnalyzer.analyze(
      StartDepAnalyzerFixtures::NamespacedConstant
    )

    assert_equal 1, result.size
    assert_equal StartDepAnalyzerFixtures::LeafTask, result.first.klass
  end

  def test_return_stops_scanning
    result = Taski::StaticAnalysis::StartDepAnalyzer.analyze(
      StartDepAnalyzerFixtures::ReturnStopsScanning
    )

    # return stops scanning — LeafTaskB after return is not collected
    assert_equal 1, result.size
    assert_equal StartDepAnalyzerFixtures::LeafTask, result.first.klass
  end

  def test_unparseable_class_returns_empty
    # Anonymous classes can't be located in AST → returns empty
    klass = Class.new(Taski::Task) do
      exports :value

      def run
        @value = "test"
      end
    end

    result = Taski::StaticAnalysis::StartDepAnalyzer.analyze(klass)
    assert_equal [], result
  end
end
