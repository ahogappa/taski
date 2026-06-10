# frozen_string_literal: true

require "test_helper"
require "timeout"
require_relative "fixtures/skip_revival_tasks"

# Characterization of the documented :skipped contract (see Scheduler and
# TaskObserver docs): :skipped means "not independently scheduled", NOT "will
# never run". A still-running task that requests a skipped task via the Fiber
# pull model revives it — observers see skipped → running → completed for the
# same task within one execution, and that sequence is legal.
class TestSkipRevival < Minitest::Test
  def setup
    Taski::Task.reset! if defined?(Taski::Task)
    Taski::StaticAnalysis::StartDepAnalyzer.clear_cache!
  end

  def test_a_skipped_task_pulled_by_a_running_task_is_revived
    root_class = SkipRevivalFixtures::ReviveRoot

    events = []
    observer = Object.new
    observer.define_singleton_method(:on_task_updated) do |tc, current_state:, **_|
      events << [tc, current_state]
    end
    observer.define_singleton_method(:on_ready) {}
    observer.define_singleton_method(:on_start) {}
    observer.define_singleton_method(:on_stop) {}

    registry = Taski::Execution::Registry.new
    facade = Taski::Execution::ExecutionFacade.new(root_task_class: root_class)
    facade.add_observer(observer)

    executor = Taski::Execution::Executor.new(
      registry: registry,
      execution_facade: facade,
      worker_count: 4
    )

    error = nil
    Timeout.timeout(15) do
      error = assert_raises(Taski::AggregateError) { executor.execute(root_class) }
    end

    shared = SkipRevivalFixtures::ReviveShared
    skipped_at = events.index([shared, :skipped])
    running_at = events.rindex([shared, :running])
    completed_at = events.index([shared, :completed])

    refute_nil skipped_at, "the dependent of the failed leaf must first be reported skipped"
    refute_nil running_at, "the pull from the still-running requester must revive it"
    refute_nil completed_at, "the revived task must complete"
    assert_operator skipped_at, :<, running_at,
      "the legal revival sequence is skipped -> running -> completed"
    assert_operator running_at, :<, completed_at

    # The revival is consistent end to end: the requester observed the revived
    # task's real value, and the failure report contains only the real failure.
    failures = error.errors.map(&:task_class)
    assert_includes failures, SkipRevivalFixtures::ReviveFailLeaf
    refute_includes failures, shared, "the revived task completed — it must not be reported failed"
  end
end
