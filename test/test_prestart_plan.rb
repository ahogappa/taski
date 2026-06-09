# frozen_string_literal: true

require "test_helper"
require "logger"
require "stringio"
require_relative "fixtures/start_dep_analyzer_tasks"

# Task.prestart_plan and the Taski.prestart_debug tree annotation surface the
# otherwise-invisible prestart heuristic: which deps are prestarted (lazy proxy
# / overlap), which are resolved synchronously, and where scanning stopped.
class TestPrestartPlan < Minitest::Test
  def setup
    Taski::StaticAnalysis::StartDepAnalyzer.clear_cache!
    Taski.prestart_debug = false
  end

  def teardown
    Taski.prestart_debug = false
  end

  def test_prestart_plan_lists_prestarted_deps
    plan = StartDepAnalyzerFixtures::MultipleAssignments.prestart_plan

    assert_equal "StartDepAnalyzerFixtures::MultipleAssignments", plan[:task]
    assert_includes plan[:prestarted], "StartDepAnalyzerFixtures::LeafTask"
    assert_includes plan[:prestarted], "StartDepAnalyzerFixtures::LeafTaskB"
    assert_empty plan[:sync]
    assert_nil plan[:stopped_at]
  end

  def test_prestart_plan_reports_sync_deps
    # `if a` demotes LeafTask to sync, and the `if` statement stops scanning.
    plan = StartDepAnalyzerFixtures::DangerConditionIf.prestart_plan

    assert_includes plan[:sync], "StartDepAnalyzerFixtures::LeafTask"
    refute_includes plan[:prestarted], "StartDepAnalyzerFixtures::LeafTask"
    refute_nil plan[:stopped_at]
  end

  def test_prestart_plan_is_empty_for_a_leaf
    plan = StartDepAnalyzerFixtures::LeafTask.prestart_plan

    assert_empty plan[:prestarted]
    assert_empty plan[:sync]
    assert_nil plan[:stopped_at]
  end

  def test_tree_is_unchanged_when_prestart_debug_off
    plain_a = StartDepAnalyzerFixtures::MultipleAssignments.tree
    plain_b = StartDepAnalyzerFixtures::MultipleAssignments.tree

    assert_equal plain_a, plain_b
  end

  def test_tree_is_annotated_when_prestart_debug_on
    plain = StartDepAnalyzerFixtures::MultipleAssignments.tree

    Taski.prestart_debug = true
    annotated = StartDepAnalyzerFixtures::MultipleAssignments.tree

    refute_equal plain, annotated
    assert_includes annotated, "prestart"
  end

  def test_prestart_plan_is_logged_at_debug_level_during_execution
    log_output = StringIO.new
    original = Taski.logger
    logger = Logger.new(log_output)
    logger.level = Logger::DEBUG
    Taski.logger = logger

    StartDepAnalyzerFixtures::MultipleAssignments.run(workers: 1)

    assert_match(/analysis\.start_dep_plan/, log_output.string)
  ensure
    Taski.logger = original
  end
end
