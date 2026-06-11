# frozen_string_literal: true

require "test_helper"
require "timeout"
require_relative "fixtures/attribution_tasks"

# AggregateError must attribute each unique error to its ORIGIN task (the one
# whose run raised). A dependency failure re-raises the same error object in
# every waiter up the requester chain; deduplication must keep the origin's
# TaskFailure, not a requester's. This is the contract the GUIDE's Error
# Handling section documents ("- DatabaseTask: Database connection failed",
# "rescue DatabaseTask::Error").
class TestFailureAttribution < Minitest::Test
  def setup
    Taski::Task.reset! if defined?(Taski::Task)
    Taski::StaticAnalysis::StartDepAnalyzer.clear_cache!
  end

  def test_propagated_failure_is_attributed_to_the_origin_task
    error = Timeout.timeout(15) do
      assert_raises(Taski::AggregateError) { AttributionFixtures::ChainRoot.run }
    end

    assert_equal 1, error.errors.size,
      "one underlying error must yield one TaskFailure"
    failure = error.errors.first
    assert_equal AttributionFixtures::OriginFail, failure.task_class,
      "the failure must name the task whose run raised, not a requester"
    assert_equal "origin boom", failure.error.message
    assert_kind_of AttributionFixtures::OriginFail::Error, failure.error,
      "the error must be wrapped as the ORIGIN's task-specific Error class"
  end

  def test_guide_documented_task_specific_rescue_matches_the_origin
    matched = false
    Timeout.timeout(15) do
      AttributionFixtures::ChainRoot.run
    rescue AttributionFixtures::OriginFail::Error
      matched = true
    end

    assert matched,
      "rescue OriginFail::Error must match the AggregateError (AggregateAware ===) — the GUIDE-documented pattern"
  end

  def test_independent_failures_are_each_attributed_to_their_own_task
    error = Timeout.timeout(15) do
      assert_raises(Taski::AggregateError) { AttributionFixtures::FanInRoot.run }
    end

    classes = error.errors.map(&:task_class)
    assert_includes classes, AttributionFixtures::IndependentFailA
    assert_includes classes, AttributionFixtures::IndependentFailB
    refute_includes classes, AttributionFixtures::FanInRoot,
      "the requester only re-raised its dependencies' errors — it must not appear"
    assert_equal 2, error.errors.size
  end

  def test_nested_executor_failures_keep_the_inner_origin_attribution
    error = Timeout.timeout(15) do
      assert_raises(Taski::AggregateError) { AttributionFixtures::NestedOuter.run }
    end

    # The inner executor attributed the failure to InnerLeaf; the outer
    # executor splices those failures through and must not re-attribute them
    # to the outer task that carried the nested AggregateError.
    assert_equal 1, error.errors.size
    assert_equal AttributionFixtures::InnerLeaf, error.errors.first.task_class
    assert_kind_of AttributionFixtures::InnerLeaf::Error, error.errors.first.error
  end
end
