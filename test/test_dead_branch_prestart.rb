# frozen_string_literal: true

require "test_helper"
require "timeout"
require_relative "fixtures/dead_branch_tasks"

# Prestart must only speculate on deps from the leading straight-line prefix of
# run — deps that sequential semantics are CERTAIN to read. A dep referenced
# only inside a never-taken branch must not be dispatched: phase-2's
# unsafe-usage scan covers the whole body, and its output must not widen the
# prestart set beyond the phase-1 prefix.
class TestDeadBranchPrestart < Minitest::Test
  def setup
    Taski::Task.reset! if defined?(Taski::Task)
    Taski::StaticAnalysis::StartDepAnalyzer.clear_cache!
    DeadBranchFixtures::DeadProbe.ran = false
  end

  # Classification: the dead-branch dep must not appear in sync_deps (which
  # feeds the prestart dispatch union) — only prefix deps are prestartable.
  def test_dead_branch_dep_is_not_in_the_prestart_sets
    result = Taski::StaticAnalysis::StartDepAnalyzer.analyze(
      DeadBranchFixtures::DeadBranchRoot
    )

    assert_includes result.start_deps, DeadBranchFixtures::Leaf
    refute_includes result.sync_deps, DeadBranchFixtures::DeadProbe,
      "a dep referenced only in a dead branch must not be dispatched via sync_deps"
    refute_includes result.start_deps, DeadBranchFixtures::DeadProbe
  end

  # Runtime: the dead-branch dep must never execute.
  def test_dead_branch_dep_does_not_execute
    Timeout.timeout(15) do
      assert_equal "root: leaf", DeadBranchFixtures::DeadBranchRoot.value
    end

    refute DeadBranchFixtures::DeadProbe.ran,
      "a dep whose only reference is inside a never-taken branch was executed"
  end

  # Runtime: a raising dead-branch dep must not fail a run that sequential
  # semantics would complete successfully.
  def test_raising_dead_branch_dep_does_not_fail_the_run
    Timeout.timeout(15) do
      assert_equal "ok: leaf", DeadBranchFixtures::DeadBranchRaisingRoot.value
    end
  end
end
