# frozen_string_literal: true

require "test_helper"
require "timeout"
require "stringio"
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

    dep_a = report.tasks.find { |t| t.name == "ProfileFixtures::SlowDepA" }
    dep_b = report.tasks.find { |t| t.name == "ProfileFixtures::SlowDepB" }
    assert_operator dep_b.duration, :>=, 0.3, "SlowDepB sleeps 0.4s"
    # Relative assertion (robust to whole-VM stalls): prestarted siblings run
    # in parallel, so B must start before A finishes.
    assert_operator dep_b.start_offset, :<, dep_a.start_offset + dep_a.duration,
      "prefix deps should run in parallel (B starts before A finishes)"
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

  def test_nested_profile_restores_the_outer_collector
    inner = nil
    outer = nil
    Timeout.timeout(15) do
      outer = Taski.profile do
        inner = Taski.profile { ProfileFixtures::SlowDepA.run(workers: 2) }
        refute_nil Taski.current_profile_collector,
          "the outer collector must be restored after the inner block"
        ProfileFixtures::SlowDepB.run(workers: 2)
        nil
      end
    end

    assert_includes inner.tasks.map(&:name), "ProfileFixtures::SlowDepA"
    refute_includes inner.tasks.map(&:name), "ProfileFixtures::SlowDepB"
    assert_includes outer.tasks.map(&:name), "ProfileFixtures::SlowDepB"
    refute_includes outer.tasks.map(&:name), "ProfileFixtures::SlowDepA",
      "the inner block's executions belong to the inner report only"
  end

  def test_failed_run_is_reported_with_failed_state
    report = nil
    Timeout.timeout(15) do
      report = Taski.profile do
        ProfileFixtures::FailingRoot.run(workers: 2)
      rescue Taski::AggregateError
        # The failure is the scenario under test; the report must still build.
      end
    end

    entry = report.tasks.find { |t| t.name == "ProfileFixtures::FailingRoot" }
    assert_equal :failed, entry.state
    assert_includes report.to_s, "(failed)"
  end

  def test_run_and_clean_records_clean_phase_entries
    report = nil
    Timeout.timeout(15) do
      report = Taski.profile { ProfileFixtures::CleanRoot.run_and_clean(workers: 2) }
    end

    assert_includes report.tasks.map(&:phase), :clean
    assert_includes report.to_s, "(clean)"
  end

  def test_value_entry_point_is_profiled
    report = nil
    Timeout.timeout(15) do
      report = Taski.profile { ProfileFixtures::ParallelRoot.value }
    end

    refute report.empty?
    assert_equal "ProfileFixtures::ParallelRoot", report.critical_path.first.name
  end

  # --- the profile: option on run / run_and_clean ---

  def test_run_profile_option_writes_report_to_the_given_io
    out = StringIO.new
    result = nil
    Timeout.timeout(15) do
      result = ProfileFixtures::ParallelRoot.run(workers: 4, profile: out)
    end

    assert_includes out.string, "Taski profile"
    assert_includes out.string, "ProfileFixtures::SlowDepB"
    assert_includes out.string, "critical path"
    assert_equal "ab", result, "the return contract must be unchanged (task result, not a report)"
  end

  def test_run_profile_true_prints_to_stdout
    out, _err = capture_io do
      Timeout.timeout(15) { ProfileFixtures::ParallelRoot.run(workers: 4, profile: true) }
    end

    assert_includes out, "critical path"
  end

  def test_run_and_clean_profile_option_includes_clean_phase
    out = StringIO.new
    Timeout.timeout(15) do
      ProfileFixtures::CleanRoot.run_and_clean(workers: 2, profile: out)
    end

    assert_includes out.string, "(clean)"
  end

  def test_run_without_profile_option_prints_nothing
    out, _err = capture_io do
      Timeout.timeout(15) { ProfileFixtures::ParallelRoot.run(workers: 4) }
    end

    refute_includes out, "Taski profile"
  end

  # Destination IO that always fails — a report-WRITE failure must not turn a
  # successful run into an exception (same isolation as report construction).
  class RaisingIO
    def puts(*)
      raise IOError, "closed stream"
    end
  end

  def test_profile_write_failure_does_not_fail_the_run
    result = nil
    capture_io do
      Timeout.timeout(15) do
        result = ProfileFixtures::ParallelRoot.run(workers: 4, profile: RaisingIO.new)
      end
    end

    assert_equal "ab", result
  end

  # NotImplementedError is a ScriptError, not a StandardError — the classic
  # Ruby trap for "write not implemented" IO-likes. Isolation must hold.
  class ScriptErrorIO
    def puts(*)
      raise NotImplementedError, "write not implemented"
    end
  end

  def test_profile_write_script_error_does_not_fail_the_run
    result = nil
    capture_io do
      Timeout.timeout(15) do
        result = ProfileFixtures::ParallelRoot.run(workers: 4, profile: ScriptErrorIO.new)
      end
    end

    assert_equal "ab", result
  end

  # A failing build is exactly when the profile matters most — the report must
  # be written before the exception is re-raised.
  def test_failing_run_with_profile_still_writes_the_report
    out = StringIO.new
    Timeout.timeout(15) do
      assert_raises(Taski::AggregateError) do
        ProfileFixtures::FailingRoot.run(workers: 2, profile: out)
      end
    end

    assert_includes out.string, "ProfileFixtures::FailingRoot"
    assert_includes out.string, "(failed)"
  end

  def test_run_and_clean_writes_run_profile_even_when_clean_fails
    out = StringIO.new
    Timeout.timeout(15) do
      assert_raises(Taski::AggregateError) do
        ProfileFixtures::FailingCleanRoot.run_and_clean(workers: 2, profile: out)
      end
    end

    assert_includes out.string, "ProfileFixtures::FailingCleanRoot",
      "the run-phase profile must survive a clean-phase failure"
  end

  # profile: "report.txt" is a plausible misreading of the IO form — it must
  # fail fast, not silently print to $stdout.
  def test_profile_option_rejects_non_io_destinations
    assert_raises(ArgumentError) do
      ProfileFixtures::ParallelRoot.run(profile: "report.txt")
    end
  end

  # A nested run(profile:) inside a task body joins the enclosing execution —
  # there is no separate event stream, so say that instead of confidently
  # writing an empty report.
  def test_nested_run_profile_writes_a_notice_instead_of_an_empty_report
    out = StringIO.new
    ProfileFixtures::NestedProfilingRoot.destination = out
    Timeout.timeout(15) do
      ProfileFixtures::NestedProfilingRoot.run(workers: 2)
    end

    assert_includes out.string, "enclosing execution"
    refute_includes out.string, "no execution recorded"
  ensure
    ProfileFixtures::NestedProfilingRoot.destination = nil
  end

  # Report-level unit test: events may arrive out of timestamp order (worker
  # threads); the report must sort before pairing intervals. Also pins the
  # frozen (immutable) result collections.
  def test_report_handles_out_of_order_events
    t0 = Time.now
    events = [
      Taski::Profile::Event.new(task_class: ProfileFixtures::SlowDepA, state: :completed, phase: :run, at: t0 + 1),
      Taski::Profile::Event.new(task_class: ProfileFixtures::SlowDepA, state: :running, phase: :run, at: t0)
    ]
    report = Taski::Profile::Report.new(events: events, root: nil, graph: nil, result: nil)

    entry = report.tasks.first
    assert_equal :completed, entry.state
    assert_in_delta 1.0, entry.duration, 0.01
    assert report.tasks.frozen?
    assert report.critical_path.frozen?
  end

  # Pins the arrival-order tie-break: equal timestamps (coarse clock) must not
  # split running/completed pairs into bogus intervals (sort_by is unstable).
  def test_equal_timestamp_events_pair_correctly
    t = Time.now
    events = Array.new(40) do
      [
        Taski::Profile::Event.new(task_class: ProfileFixtures::SlowDepA, state: :running, phase: :run, at: t),
        Taski::Profile::Event.new(task_class: ProfileFixtures::SlowDepA, state: :completed, phase: :run, at: t)
      ]
    end.flatten
    report = Taski::Profile::Report.new(events: events, root: nil, graph: nil, result: nil)

    assert_equal 40, report.tasks.size
    assert(report.tasks.all? { |e| e.state == :completed },
      "every :running must pair with its :completed even on equal timestamps")
  end

  # Pins the skipped-reconciliation guard: a :skipped event for a class whose
  # timeline already has a real interval must not add a contradictory row.
  def test_skipped_event_after_a_real_run_is_reconciled
    t0 = Time.now
    events = [
      Taski::Profile::Event.new(task_class: ProfileFixtures::SlowDepA, state: :running, phase: :run, at: t0),
      Taski::Profile::Event.new(task_class: ProfileFixtures::SlowDepA, state: :completed, phase: :run, at: t0 + 1),
      Taski::Profile::Event.new(task_class: ProfileFixtures::SlowDepA, state: :skipped, phase: :run, at: t0 + 1)
    ]
    report = Taski::Profile::Report.new(events: events, root: nil, graph: nil, result: nil)

    assert_equal 1, report.tasks.size
    assert_equal :completed, report.tasks.first.state
  end

  # Pins the bounding-interval critical path: for re-runs of the same root in
  # one block, the path renders the LATEST-finishing interval, not the first.
  def test_critical_path_renders_the_latest_finishing_interval_for_reruns
    report = nil
    Timeout.timeout(30) do
      report = Taski.profile do
        ProfileFixtures::ParallelRoot.run(workers: 4)
        ProfileFixtures::ParallelRoot.run(workers: 4)
      end
    end

    assert_operator report.critical_path.first.start_offset, :>, 0.4,
      "the critical path must render the second (bounding) run's interval"
  end

  # Report-CONSTRUCTION failure must not turn a successful block into an
  # exception (mirror of the write-path isolation tests).
  def test_report_build_failure_degrades_to_empty_report
    original = Taski::Profile::Report.method(:build)
    Taski::Profile::Report.define_singleton_method(:build) { |*| raise "boom in build" }

    report = Taski.profile { 42 }

    assert report.empty?
    assert_equal 42, report.result
  ensure
    Taski::Profile::Report.define_singleton_method(:build, original)
  end
end
