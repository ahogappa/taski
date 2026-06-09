# frozen_string_literal: true

require "test_helper"
require "timeout"
require_relative "fixtures/args_tasks"

# Taski.args / Taski.env are per-execution state. Two concurrent top-level
# Task.run / .value calls on different threads must each see their OWN args and
# env — they must not share a single process-wide set (which would silently drop
# the second caller's args).
class TestConcurrentArgsIsolation < Minitest::Test
  def setup
    Taski::Task.reset! if defined?(Taski::Task)
    ArgsFixtures::CapturedValues.clear
  end

  def teardown
    ArgsFixtures::ConcurrentArgsTask.barrier = nil
    ArgsFixtures::ConcurrentArgsTask.sink = nil
  end

  # A 2-party rendezvous: both callers block until both have entered the guarded
  # region, guaranteeing their args lifecycles overlap in time.
  def make_barrier(parties)
    mutex = Mutex.new
    cond = ConditionVariable.new
    count = 0
    lambda do
      mutex.synchronize do
        count += 1
        cond.broadcast if count >= parties
        cond.wait(mutex, 1) until count >= parties
      end
    end
  end

  # Caller-thread level: two threads each open their own with_args and must read
  # back their own options, even while both are open simultaneously.
  def test_with_args_is_isolated_between_threads
    Timeout.timeout(10) do
      barrier = make_barrier(2)
      seen = {}
      seen_mutex = Mutex.new

      threads = %w[X Y].map do |id|
        Thread.new do
          Taski.send(:with_args, options: {id: id}) do
            barrier.call # both threads are now inside their own with_args
            seen_mutex.synchronize { seen[id] = Taski.args[:id] }
          end
        end
      end
      threads.each(&:join)

      assert_equal({"X" => "X", "Y" => "Y"}, seen,
        "each thread's with_args must be independent, not a shared singleton")
    end
  end

  # Caller-thread level for env: same isolation guarantee for Taski.env.
  def test_with_env_is_isolated_between_threads
    Timeout.timeout(10) do
      barrier = make_barrier(2)
      seen = {}
      seen_mutex = Mutex.new

      threads = [ArgsFixtures::DepTask, ArgsFixtures::RootConsistencyTask].map do |root|
        Thread.new do
          Taski.send(:with_env, root_task: root) do
            barrier.call
            seen_mutex.synchronize { seen[root] = Taski.env.root_task }
          end
        end
      end
      threads.each(&:join)

      assert_equal ArgsFixtures::DepTask, seen[ArgsFixtures::DepTask]
      assert_equal ArgsFixtures::RootConsistencyTask, seen[ArgsFixtures::RootConsistencyTask]
    end
  end

  # Full execution: two concurrent Task.run calls with different args, forced to
  # overlap, must each have their worker see their own marker.
  def test_concurrent_top_level_runs_see_their_own_args
    Timeout.timeout(20) do
      sink = Queue.new
      ArgsFixtures::ConcurrentArgsTask.barrier = make_barrier(2)
      ArgsFixtures::ConcurrentArgsTask.sink = sink

      threads = %w[alpha bravo].map do |marker|
        Thread.new do
          ArgsFixtures::ConcurrentArgsTask.run(args: {marker: marker}, workers: 1)
        end
      end
      threads.each { |t| t.join(15) }

      seen = [sink.pop, sink.pop].sort
      assert_equal %w[alpha bravo], seen,
        "each concurrent execution's worker must observe its own args"
    end
  end
end
