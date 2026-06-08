# frozen_string_literal: true

require "test_helper"
require_relative "fixtures/fan_in_tasks"

class TestFanInRecursion < Minitest::Test
  def setup
    Taski::Task.reset! if defined?(Taski::Task)
  end

  # Reading a large number of already-completed dependencies must not overflow
  # the worker stack. drive_fiber_loop must iterate over resolved dependencies
  # rather than recursing once per resolution.
  def test_many_completed_dependency_reads_do_not_overflow_stack
    total = nil

    Timeout.timeout(30) do
      total = FanInFixtures::DeepFanInRoot.total(args: {})
    end

    assert_equal FanInFixtures::DeepFanInRoot::READS, total
  end
end
