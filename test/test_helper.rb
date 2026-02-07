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

  # Build a task instance bypassing private Task.new
  # This mirrors the pattern used by production code (fresh_wrapper).
  def self.build_task_instance(task_class)
    instance = task_class.allocate
    instance.__send__(:initialize)
    instance
  end
end
