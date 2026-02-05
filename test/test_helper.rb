# frozen_string_literal: true

# SimpleCov setup for code coverage (only in CI or when explicitly requested)
if ENV["CI"] || ENV["COVERAGE"]
  require "simplecov"
  require "simplecov-lcov"

  SimpleCov::Formatter::LcovFormatter.config.report_with_single_file = true
  SimpleCov.formatter = SimpleCov::Formatter::MultiFormatter.new([
    SimpleCov::Formatter::HTMLFormatter,
    SimpleCov::Formatter::LcovFormatter
  ])

  SimpleCov.start do
    add_filter "/test/"
    add_filter "/examples/"
    add_filter "/pkg/"
    add_filter "/sig/"

    add_group "Core", "lib/taski.rb"
    add_group "Parallel Execution", "lib/taski/parallel"
    add_group "Static Analysis", "lib/taski/parallel/static_analysis"
    add_group "Execution Engine", "lib/taski/parallel/execution"
  end
end

require "minitest/autorun"
require "timeout"
require_relative "../lib/taski"

# Common test helper functionality for Taski tests
module TaskiTestHelper
  # Test setup method to be included in test classes
  def setup_taski_test
    # Reset the parallel execution system
    Taski::Task.reset! if defined?(Taski::Task)
  end
end

# Helper for Layout tests to simulate state transitions via on_task_updated
module LayoutTestHelper
  # Simulate task starting (pending -> running)
  def simulate_task_start(layout, task_class, timestamp: Time.now)
    layout.on_task_updated(task_class, previous_state: :pending, current_state: :running, timestamp: timestamp)
  end

  # Simulate task completion (running -> completed)
  # Duration is calculated from timestamps, so pass start_time to control duration
  def simulate_task_complete(layout, task_class, timestamp: Time.now)
    layout.on_task_updated(task_class, previous_state: :running, current_state: :completed, timestamp: timestamp)
  end

  # Simulate task failure (running -> failed)
  # Note: error is not passed via notification - exceptions propagate to top level (Plan design)
  def simulate_task_fail(layout, task_class, timestamp: Time.now)
    layout.on_task_updated(task_class, previous_state: :running, current_state: :failed, timestamp: timestamp)
  end

  # Simulate task skip (pending -> skipped)
  def simulate_task_skip(layout, task_class, timestamp: Time.now)
    layout.on_task_updated(task_class, previous_state: :pending, current_state: :skipped, timestamp: timestamp)
  end
end
