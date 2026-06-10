# frozen_string_literal: true

require "test_helper"
require "timeout"
require_relative "fixtures/profile_tasks"

# Taski.profile { ... } records task state transitions during the block's
# executions (as a pure additional observer — execution is unchanged) and
# returns a Report: per-task start offsets and durations, plus the critical
# path. It is a mirror, not advice: it shows where the time went.
class TestProfile < Minitest::Test
  def setup
    Taski::Task.reset! if defined?(Taski::Task)
    Taski::StaticAnalysis::StartDepAnalyzer.clear_cache!
  end

  def test_profile_records_intervals_for_every_task
    report = nil
    Timeout.timeout(15) do
      report = Taski.profile { ProfileFixtures::ParallelRoot.run(workers: 4) }
    end

    names = report.tasks.map(&:name)
    assert_includes names, "ProfileFixtures::ParallelRoot"
    assert_includes names, "ProfileFixtures::SlowDepA"
    assert_includes names, "ProfileFixtures::SlowDepB"

    dep_b = report.tasks.find { |t| t.name == "ProfileFixtures::SlowDepB" }
    assert_operator dep_b.duration, :>=, 0.3, "SlowDepB sleeps 0.4s"
    assert_operator dep_b.start_offset, :<, 0.2, "prefix dep should start near t=0 (prestarted)"
  end

  def test_profile_surfaces_late_started_dep
    report = nil
    Timeout.timeout(15) do
      report = Taski.profile { ProfileFixtures::LazyRoot.run(workers: 4) }
    end

    dep = report.tasks.find { |t| t.name == "ProfileFixtures::SlowDepA" }
    assert_operator dep.start_offset, :>=, 0.25,
      "a dep read after 0.3s of inline work starts late — the signal the profile exists to show"
  end

  def test_critical_path_descends_to_the_slowest_dep
    report = nil
    Timeout.timeout(15) do
      report = Taski.profile { ProfileFixtures::ParallelRoot.run(workers: 4) }
    end

    assert_equal ["ProfileFixtures::ParallelRoot", "ProfileFixtures::SlowDepB"],
      report.critical_path.map(&:name)
  end

  def test_to_s_renders_a_readable_report
    report = nil
    Timeout.timeout(15) do
      report = Taski.profile { ProfileFixtures::ParallelRoot.run(workers: 4) }
    end

    text = report.to_s
    assert_includes text, "ProfileFixtures::ParallelRoot"
    assert_includes text, "ProfileFixtures::SlowDepB"
    assert_includes text, "critical path"
  end

  def test_profile_without_execution_returns_empty_report
    report = Taski.profile { "nothing" }

    assert_empty report.tasks
    assert report.empty?
    assert_includes report.to_s, "no execution"
  end

  def test_profile_exposes_the_block_result
    report = Taski.profile { 42 }

    assert_equal 42, report.result
  end

  def test_profile_does_not_leak_into_later_runs
    report = nil
    Timeout.timeout(15) do
      report = Taski.profile { ProfileFixtures::ParallelRoot.run(workers: 4) }

      # The collector slot must be cleared once the block exits...
      assert_nil Taski.current_profile_collector

      # ...so a later run is not recorded into the old report.
      recorded = report.tasks.size
      ProfileFixtures::ParallelRoot.run(workers: 4)
      assert_equal recorded, report.tasks.size
    end
  end
end
