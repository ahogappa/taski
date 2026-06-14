# frozen_string_literal: true

require "test_helper"
require "stringio"
require_relative "fixtures/display_reset_tasks"

# The progress display is a persistent singleton (Config#build memoizes it), so
# it is reused across sequential top-level executions in one process. It must
# reset its per-execution state (root, task tallies, tree) for each new
# top-level execution — otherwise the second execution renders the first's
# root name and an accumulated task count.
class TestDisplayResetBetweenExecutions < Minitest::Test
  def setup
    Taski::Task.reset! if defined?(Taski::Task)
    Taski::StaticAnalysis::StartDepAnalyzer.clear_cache!
  end

  def teardown
    Taski.reset_progress_display!
  end

  def test_second_top_level_execution_shows_its_own_root_and_count
    out = StringIO.new
    Taski.progress.layout = Taski::Progress::Layout::Tree
    Taski.progress.output = out

    DisplayResetFixtures::FirstRoot.run
    DisplayResetFixtures::SecondRoot.run

    text = out.string.gsub(/\e\[[0-9;?]*[a-zA-Z]/, "")

    # The second execution must name its OWN root, not the first's (stale).
    assert_includes text, "Starting SecondRoot",
      "the second execution must display its own root"

    # Each execution has exactly one task; neither summary may accumulate the
    # other's tasks.
    completed = text.lines.grep(/\[TASKI\] Completed:/)
    assert_equal 2, completed.size, "one completion summary per execution"
    completed.each do |line|
      assert_match(%r{1/1 tasks}, line,
        "each execution counts only its own tasks (no accumulation): #{line.inspect}")
    end
  end

  # run_and_clean calls notify_start BEFORE its first on_ready, so the reset
  # must happen when the previous execution STOPS (not lazily at the next
  # on_ready) — otherwise the second run_and_clean's tasks accumulate and its
  # root stays stale. Pinning this separately from plain .run.
  def test_second_run_and_clean_does_not_accumulate_tasks
    out = StringIO.new
    Taski.progress.layout = Taski::Progress::Layout::Tree
    Taski.progress.output = out

    DisplayResetFixtures::FirstRoot.run_and_clean
    DisplayResetFixtures::SecondRoot.run_and_clean

    text = out.string.gsub(/\e\[[0-9;?]*[a-zA-Z]/, "")

    # The second execution renders its own task, not the first's.
    assert_includes text, "SecondRoot"
    completed = text.lines.grep(/\[TASKI\] Completed:/)
    assert_equal 2, completed.size
    completed.each do |line|
      assert_match(%r{1/1 tasks}, line,
        "each run_and_clean counts only its own tasks (no accumulation): #{line.inspect}")
    end
  end

  # The reset happens at stop: after a top-level execution finishes, the
  # display holds no leftover task/root state.
  def test_display_state_is_cleared_after_an_execution_stops
    Taski.progress.layout = Taski::Progress::Layout::Log
    Taski.progress.output = StringIO.new

    DisplayResetFixtures::FirstRoot.run
    display = Taski.progress_display

    refute display.task_registered?(DisplayResetFixtures::FirstRoot),
      "per-execution task state must be cleared once the execution stops"
  end

  def test_display_singleton_is_actually_reused_across_executions
    # Guards the premise: if the display were rebuilt per execution the bug
    # could not occur and the test above would be vacuous.
    Taski.progress.layout = Taski::Progress::Layout::Log
    Taski.progress.output = StringIO.new

    DisplayResetFixtures::FirstRoot.run
    first = Taski.progress_display
    DisplayResetFixtures::SecondRoot.run
    second = Taski.progress_display

    assert_same first, second, "the global progress display is reused across executions"
  end
end
