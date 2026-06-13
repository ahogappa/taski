# frozen_string_literal: true

require "test_helper"

# Task#group must notify completion on EVERY exit path — normal return,
# raise, and non-local exits (break / return / throw / non-StandardError).
# A missed completion leaks the group open in the display bookkeeping
# (@group_start_times), leaving a stale "GroupName:" caption on the status
# line for the rest of the run and the clean phase.
#
# Component test: drives Task#group directly against a recording facade —
# no task execution pipeline involved (Class.new is fine per CLAUDE.md).
class TestTaskGroup < Minitest::Test
  class RecordingFacade
    attr_reader :events

    def initialize
      @events = []
    end

    def notify_group_started(task_class, name, phase:, timestamp:)
      @events << [:started, name]
    end

    def notify_group_completed(task_class, name, phase:, timestamp:)
      @events << [:completed, name]
    end
  end

  def setup
    @facade = RecordingFacade.new
    Taski::Execution::ExecutionFacade.current = @facade
    # Task.new is private; the framework itself builds instances via allocate
    # (lib/taski/task.rb run_with_execution), so the component test does too.
    @task = Class.new(Taski::Task) {
      def run
      end
    }.allocate
  end

  def teardown
    Taski::Execution::ExecutionFacade.current = nil
  end

  def test_group_completes_on_normal_exit_and_returns_block_result
    result = @task.group("Phase") { :value }

    assert_equal :value, result
    assert_equal [[:started, "Phase"], [:completed, "Phase"]], @facade.events
  end

  def test_group_completes_when_block_raises
    assert_raises(RuntimeError) { @task.group("Phase") { raise "boom" } }

    assert_equal [[:started, "Phase"], [:completed, "Phase"]], @facade.events
  end

  def test_group_completes_when_block_breaks
    @task.group("Phase") { break }

    assert_equal [[:started, "Phase"], [:completed, "Phase"]], @facade.events
  end

  def test_group_completes_when_block_returns_from_enclosing_method
    helper = lambda do |task|
      task.group("Phase") { return :early }
    end
    helper.call(@task)

    assert_equal [[:started, "Phase"], [:completed, "Phase"]], @facade.events
  end

  def test_group_completes_when_block_throws
    catch(:abort_run) do
      @task.group("Phase") { throw :abort_run }
    end

    assert_equal [[:started, "Phase"], [:completed, "Phase"]], @facade.events
  end

  def test_group_completes_when_block_raises_non_standard_error
    assert_raises(NotImplementedError) { @task.group("Phase") { raise NotImplementedError, "nope" } }

    assert_equal [[:started, "Phase"], [:completed, "Phase"]], @facade.events
  end
end
