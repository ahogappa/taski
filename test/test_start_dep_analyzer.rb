# frozen_string_literal: true

require "test_helper"
require "timeout"
require_relative "fixtures/start_dep_analyzer_tasks"

class TestStartDepAnalyzer < Minitest::Test
  def setup
    Taski::StaticAnalysis::StartDepAnalyzer.clear_cache!
  end

  # Prestart analysis degrades to "no prestart" on any internal error, but the
  # error must be logged (not swallowed silently) so a real analysis bug is
  # diagnosable rather than invisible.
  def test_analyze_logs_when_analysis_unexpectedly_raises
    require "logger"
    require "stringio"
    log_output = StringIO.new
    original_logger = Taski.logger
    Taski.logger = Logger.new(log_output)
    original_parse = Prism.method(:parse_file)

    result = begin
      Prism.define_singleton_method(:parse_file) { |*| raise "boom in prism" }
      Taski::StaticAnalysis::StartDepAnalyzer.analyze(StartDepAnalyzerFixtures::LeafTask)
    ensure
      Prism.define_singleton_method(:parse_file, original_parse)
      Taski.logger = original_logger
    end

    # Still degrades gracefully (tasks run via the lazy pull model)...
    assert_equal Taski::StaticAnalysis::StartDepAnalyzer::EMPTY_RESULT, result
    # ...but the unexpected failure is surfaced in the log.
    assert_match(/analysis\.start_dep_failed/, log_output.string)
    assert_match(/boom in prism/, log_output.string)
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

  def test_analyze_degrades_to_empty_when_source_file_unreadable
    require "tempfile"

    file = Tempfile.new(["start_dep_missing_source", ".rb"])
    file.write(<<~RUBY)
      module StartDepMissingSourceFixture
        class Task1 < Taski::Task
          exports :value
          def run
            @value = "x"
          end
        end
      end
    RUBY
    file.close
    load file.path
    klass = StartDepMissingSourceFixture::Task1

    Taski::StaticAnalysis::StartDepAnalyzer.clear_cache!
    File.delete(file.path) # Prism.parse_file now raises Errno::ENOENT

    result = Taski::StaticAnalysis::StartDepAnalyzer.analyze(klass)

    assert_equal Taski::StaticAnalysis::StartDepAnalyzer::EMPTY_RESULT, result
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

  def test_danger_exported_ivar_read_as_argument
    result = Taski::StaticAnalysis::StartDepAnalyzer.analyze(
      StartDepAnalyzerFixtures::DangerExportedIvarReadAsArgument
    )
    # An exported ivar holding a proxy that is later read unsafely must be a
    # sync_dep, not a start_dep, or the proxy leaks into the unsafe context.
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

  # ========================================
  # Phase 2: Non-exported ivar proxy tracking
  # ========================================

  def test_safe_non_exported_ivar_receiver
    result = Taski::StaticAnalysis::StartDepAnalyzer.analyze(
      StartDepAnalyzerFixtures::SafeNonExportedIvarReceiver
    )
    # @cache used as receiver only → safe
    assert_empty result.sync_deps
    assert_includes result.start_deps, StartDepAnalyzerFixtures::LeafTask
  end

  def test_safe_exported_ivar
    result = Taski::StaticAnalysis::StartDepAnalyzer.analyze(
      StartDepAnalyzerFixtures::SafeExportedIvar
    )
    # @value is exported → resolve_proxy_exports handles it → safe
    assert_empty result.sync_deps
    assert_includes result.start_deps, StartDepAnalyzerFixtures::LeafTask
  end

  def test_safe_direct_non_exported_ivar
    result = Taski::StaticAnalysis::StartDepAnalyzer.analyze(
      StartDepAnalyzerFixtures::SafeDirectNonExportedIvar
    )
    # @cache = Dep.value, used as receiver → safe
    assert_empty result.sync_deps
    assert_includes result.start_deps, StartDepAnalyzerFixtures::LeafTask
  end

  def test_danger_non_exported_ivar_condition
    result = Taski::StaticAnalysis::StartDepAnalyzer.analyze(
      StartDepAnalyzerFixtures::DangerNonExportedIvarCondition
    )
    # @flag used in if condition → unsafe
    assert_includes result.sync_deps, StartDepAnalyzerFixtures::LeafTask
    refute_includes result.start_deps, StartDepAnalyzerFixtures::LeafTask
  end

  def test_danger_non_exported_ivar_argument
    result = Taski::StaticAnalysis::StartDepAnalyzer.analyze(
      StartDepAnalyzerFixtures::DangerNonExportedIvarArgument
    )
    # @data used as argument → unsafe
    assert_includes result.sync_deps, StartDepAnalyzerFixtures::LeafTask
    refute_includes result.start_deps, StartDepAnalyzerFixtures::LeafTask
  end

  # ========================================
  # W1/W2 walls: proxy used in a truthiness (W1) or === (W2) position MUST be
  # demoted to sync, or it silently misbehaves (truthiness/=== bypass the proxy
  # at the C level). Classification + end-to-end runtime-result guards.
  # ========================================

  # --- classification: the dep is demoted to sync, never a start_dep proxy ---

  {
    test_wall_case_when_subject: :CaseWhenSubject,
    test_wall_case_in_subject: :CaseInSubject,
    test_wall_and_left_operand: :AndOperand,
    test_wall_or_left_operand: :OrOperand,
    test_wall_ternary_condition: :TernaryCondition,
    test_wall_if_with_nested_and: :IfWithNestedAnd,
    test_wall_chained_and_middle: :ChainedAndMiddle
  }.each do |test_name, fixture|
    define_method(test_name) do
      result = Taski::StaticAnalysis::StartDepAnalyzer.analyze(
        StartDepAnalyzerFixtures.const_get(fixture)
      )
      dep = result.sync_deps.first || result.start_deps.first
      refute_nil dep, "#{fixture}: expected a dependency to be analyzed"
      assert_empty result.start_deps,
        "#{fixture}: a proxy at a W1/W2 wall must be sync, never a start_dep"
      refute_empty result.sync_deps, "#{fixture}: the wall dep must be in sync_deps"
    end
  end

  # --- runtime: executing the task returns the correct value (no silent leak) ---

  def test_wall_runtime_results_have_no_silent_leak
    Timeout.timeout(15) do
      assert_equal "matched-String", StartDepAnalyzerFixtures::CaseWhenSubject.value
      assert_equal "matched-String", StartDepAnalyzerFixtures::CaseInSubject.value
      assert_equal false, StartDepAnalyzerFixtures::AndOperand.value
      assert_equal "fallback", StartDepAnalyzerFixtures::OrOperand.value
      assert_equal "else-branch", StartDepAnalyzerFixtures::TernaryCondition.value
      assert_equal "else-branch", StartDepAnalyzerFixtures::IfWithNestedAnd.value
      assert_equal false, StartDepAnalyzerFixtures::ChainedAndMiddle.value
    end
  end

  # `!proxy` is NOT a wall: it is a method call on the proxy (receiver), which
  # TaskProxy resolves — so the dep stays a start_dep AND `!false` is correct.
  def test_negation_is_not_a_wall
    result = Taski::StaticAnalysis::StartDepAnalyzer.analyze(
      StartDepAnalyzerFixtures::NegationSafe
    )
    assert_includes result.start_deps, StartDepAnalyzerFixtures::FalseLeaf
    assert_empty result.sync_deps

    Timeout.timeout(15) do
      assert_equal true, StartDepAnalyzerFixtures::NegationSafe.value
    end
  end
end
