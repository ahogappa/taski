# frozen_string_literal: true

require "test_helper"
require "timeout"
require_relative "fixtures/speculative_completion_tasks"

# Every dispatched task must reach a terminal state before run() returns —
# speculation must not outlive the execution. A prestarted task parked on a
# slow dep when the root finishes must be resumed and run to completion
# (its ensure must execute), not silently abandoned mid-run.
class TestSpeculativeCompletion < Minitest::Test
  def setup
    Taski::Task.reset! if defined?(Taski::Task)
    Taski::StaticAnalysis::StartDepAnalyzer.clear_cache!
    SpeculativeCompletionFixtures::SpeculativeOuter.completed = false
    SpeculativeCompletionFixtures::SpeculativeOuter.ensure_ran = false
  end

  def test_speculative_task_parked_on_slow_dep_runs_to_completion
    Timeout.timeout(15) do
      SpeculativeCompletionFixtures::FastRoot.run(workers: 4)
    end

    assert SpeculativeCompletionFixtures::SpeculativeOuter.completed,
      "a prestarted task parked on a slow dep was abandoned instead of run to completion"
    assert SpeculativeCompletionFixtures::SpeculativeOuter.ensure_ran,
      "the abandoned task's ensure block never executed"
  end
end
