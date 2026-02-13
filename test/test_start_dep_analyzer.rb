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

    assert_equal 1, result.start_deps.size
    assert_includes result.start_deps, StartDepAnalyzerFixtures::LeafTask
  end

  def test_instance_variable_assignment_dep
    result = Taski::StaticAnalysis::StartDepAnalyzer.analyze(
      StartDepAnalyzerFixtures::IvarAssignment
    )

    assert_equal 1, result.start_deps.size
    assert_includes result.start_deps, StartDepAnalyzerFixtures::LeafTask
  end

  def test_multiple_assignment_deps
    result = Taski::StaticAnalysis::StartDepAnalyzer.analyze(
      StartDepAnalyzerFixtures::MultipleAssignments
    )

    assert_equal 2, result.start_deps.size
    assert_includes result.start_deps, StartDepAnalyzerFixtures::LeafTask
    assert_includes result.start_deps, StartDepAnalyzerFixtures::LeafTaskB
  end

  def test_same_class_deduplicated
    result = Taski::StaticAnalysis::StartDepAnalyzer.analyze(
      StartDepAnalyzerFixtures::DedupAssignment
    )

    assert_equal 1, result.start_deps.size
    assert_includes result.start_deps, StartDepAnalyzerFixtures::LeafTask
  end

  def test_non_dep_assignment_continues_scanning
    result = Taski::StaticAnalysis::StartDepAnalyzer.analyze(
      StartDepAnalyzerFixtures::NonDepAssignment
    )

    assert_equal 1, result.start_deps.size
    assert_includes result.start_deps, StartDepAnalyzerFixtures::LeafTask
  end

  def test_unknown_pattern_stops_scanning
    result = Taski::StaticAnalysis::StartDepAnalyzer.analyze(
      StartDepAnalyzerFixtures::UnknownPatternStops
    )

    # if statement stops scanning, only LeafTask (before if) is returned
    assert_equal 1, result.start_deps.size
    assert_includes result.start_deps, StartDepAnalyzerFixtures::LeafTask
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

    assert_equal 1, result.start_deps.size
    assert_includes result.start_deps, StartDepAnalyzerFixtures::LeafTask
  end

  def test_return_stops_scanning
    result = Taski::StaticAnalysis::StartDepAnalyzer.analyze(
      StartDepAnalyzerFixtures::ReturnStopsScanning
    )

    # return stops scanning — LeafTaskB after return is not collected
    assert_equal 1, result.start_deps.size
    assert_includes result.start_deps, StartDepAnalyzerFixtures::LeafTask
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
    assert_empty result.start_deps
    assert_empty result.sync_deps
  end

  def test_analysis_result_has_empty_sync_deps_by_default
    result = Taski::StaticAnalysis::StartDepAnalyzer.analyze(
      StartDepAnalyzerFixtures::LocalVarAssignment
    )

    assert_instance_of Set, result.sync_deps
    assert_empty result.sync_deps
  end

  # ========================================
  # Phase 2: Danger Pattern Detection
  # ========================================

  def test_danger_arg_comparison
    result = Taski::StaticAnalysis::StartDepAnalyzer.analyze(
      StartDepAnalyzerFixtures::DangerArgComparison
    )
    assert_includes result.sync_deps, StartDepAnalyzerFixtures::LeafTask
    refute_includes result.start_deps, StartDepAnalyzerFixtures::LeafTask
  end

  def test_danger_arg_include
    result = Taski::StaticAnalysis::StartDepAnalyzer.analyze(
      StartDepAnalyzerFixtures::DangerArgInclude
    )
    assert_includes result.sync_deps, StartDepAnalyzerFixtures::LeafTask
    refute_includes result.start_deps, StartDepAnalyzerFixtures::LeafTask
  end

  def test_danger_arg_method_call
    result = Taski::StaticAnalysis::StartDepAnalyzer.analyze(
      StartDepAnalyzerFixtures::DangerArgMethodCall
    )
    # b is argument → sync, a is receiver → safe (start_dep)
    assert_includes result.sync_deps, StartDepAnalyzerFixtures::LeafTaskB
    refute_includes result.sync_deps, StartDepAnalyzerFixtures::LeafTask
    assert_includes result.start_deps, StartDepAnalyzerFixtures::LeafTask
    refute_includes result.start_deps, StartDepAnalyzerFixtures::LeafTaskB
  end

  def test_danger_condition_if
    result = Taski::StaticAnalysis::StartDepAnalyzer.analyze(
      StartDepAnalyzerFixtures::DangerConditionIf
    )
    assert_includes result.sync_deps, StartDepAnalyzerFixtures::LeafTask
    refute_includes result.start_deps, StartDepAnalyzerFixtures::LeafTask
  end

  def test_danger_condition_unless
    result = Taski::StaticAnalysis::StartDepAnalyzer.analyze(
      StartDepAnalyzerFixtures::DangerConditionUnless
    )
    assert_includes result.sync_deps, StartDepAnalyzerFixtures::LeafTask
    refute_includes result.start_deps, StartDepAnalyzerFixtures::LeafTask
  end

  def test_danger_condition_while
    result = Taski::StaticAnalysis::StartDepAnalyzer.analyze(
      StartDepAnalyzerFixtures::DangerConditionWhile
    )
    assert_includes result.sync_deps, StartDepAnalyzerFixtures::LeafTask
    refute_includes result.start_deps, StartDepAnalyzerFixtures::LeafTask
  end

  def test_danger_condition_until
    result = Taski::StaticAnalysis::StartDepAnalyzer.analyze(
      StartDepAnalyzerFixtures::DangerConditionUntil
    )
    assert_includes result.sync_deps, StartDepAnalyzerFixtures::LeafTask
    refute_includes result.start_deps, StartDepAnalyzerFixtures::LeafTask
  end

  def test_safe_receiver_only
    result = Taski::StaticAnalysis::StartDepAnalyzer.analyze(
      StartDepAnalyzerFixtures::SafeReceiverOnly
    )
    assert_empty result.sync_deps
    assert_includes result.start_deps, StartDepAnalyzerFixtures::LeafTask
  end

  def test_safe_interpolation
    result = Taski::StaticAnalysis::StartDepAnalyzer.analyze(
      StartDepAnalyzerFixtures::SafeInterpolation
    )
    assert_empty result.sync_deps
    assert_includes result.start_deps, StartDepAnalyzerFixtures::LeafTask
  end

  def test_safe_ivar_assignment
    result = Taski::StaticAnalysis::StartDepAnalyzer.analyze(
      StartDepAnalyzerFixtures::SafeIvarAssignment
    )
    assert_empty result.sync_deps
    assert_includes result.start_deps, StartDepAnalyzerFixtures::LeafTask
  end

  def test_mixed_safe_and_danger
    result = Taski::StaticAnalysis::StartDepAnalyzer.analyze(
      StartDepAnalyzerFixtures::MixedSafeAndDanger
    )
    # a is receiver → safe (start_dep); b is argument → sync
    assert_includes result.sync_deps, StartDepAnalyzerFixtures::LeafTaskB
    refute_includes result.sync_deps, StartDepAnalyzerFixtures::LeafTask
    assert_includes result.start_deps, StartDepAnalyzerFixtures::LeafTask
    refute_includes result.start_deps, StartDepAnalyzerFixtures::LeafTaskB
  end

  def test_multiple_danger_uses
    result = Taski::StaticAnalysis::StartDepAnalyzer.analyze(
      StartDepAnalyzerFixtures::MultipleDangerUses
    )
    # condition usage makes it danger even if also used as receiver
    assert_includes result.sync_deps, StartDepAnalyzerFixtures::LeafTask
    refute_includes result.start_deps, StartDepAnalyzerFixtures::LeafTask
  end

  def test_unknown_usage_falls_to_sync
    result = Taski::StaticAnalysis::StartDepAnalyzer.analyze(
      StartDepAnalyzerFixtures::UnknownUsageFallsToSync
    )
    assert_includes result.sync_deps, StartDepAnalyzerFixtures::LeafTask
    refute_includes result.start_deps, StartDepAnalyzerFixtures::LeafTask
  end

  def test_safe_reassign_to_ivar
    result = Taski::StaticAnalysis::StartDepAnalyzer.analyze(
      StartDepAnalyzerFixtures::SafeReassignToIvar
    )
    assert_empty result.sync_deps
    assert_includes result.start_deps, StartDepAnalyzerFixtures::LeafTask
  end

  def test_safe_chained_receiver
    result = Taski::StaticAnalysis::StartDepAnalyzer.analyze(
      StartDepAnalyzerFixtures::SafeChainedReceiver
    )
    assert_empty result.sync_deps
    assert_includes result.start_deps, StartDepAnalyzerFixtures::LeafTask
  end

  # ========================================
  # New: Allowlist result structure tests
  # ========================================

  def test_start_deps_and_sync_deps_are_disjoint
    result = Taski::StaticAnalysis::StartDepAnalyzer.analyze(
      StartDepAnalyzerFixtures::MixedSafeAndDanger
    )
    # start_deps and sync_deps must have no overlap
    intersection = result.start_deps & result.sync_deps
    assert_empty intersection
  end

  def test_start_deps_is_set_of_classes
    result = Taski::StaticAnalysis::StartDepAnalyzer.analyze(
      StartDepAnalyzerFixtures::MultipleAssignments
    )
    assert_instance_of Set, result.start_deps
    result.start_deps.each do |dep|
      assert_kind_of Class, dep
    end
  end

  def test_sync_deps_is_set_of_classes
    result = Taski::StaticAnalysis::StartDepAnalyzer.analyze(
      StartDepAnalyzerFixtures::DangerArgComparison
    )
    assert_instance_of Set, result.sync_deps
    result.sync_deps.each do |dep|
      assert_kind_of Class, dep
    end
  end
end
