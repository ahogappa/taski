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
    add_group "Tasks", "lib/taski/task"
    add_group "Utilities", "lib/taski"
  end
end

require "minitest/autorun"
require "timeout"
require_relative "../lib/taski"

# Common test helper functionality for Taski tests
module TaskiTestHelper
  # Class methods for tracking build order
  @build_order = []

  def self.track_build_order(component)
    @build_order ||= []
    @build_order << component
  end

  def self.build_order
    @build_order || []
  end

  def self.reset_build_order
    @build_order = []
  end

  # Test setup method to be included in test classes
  def setup_taski_test
    # Clean up any constants that might be left from previous tests
    cleanup_test_constants

    # Clear build order
    TaskiTestHelper.reset_build_order

    # Reset task instances using public API
    Taski::Task.reset!

    # Clean up test modules
    Object.send(:remove_const, :TestModule) if Object.const_defined?(:TestModule)
  end

  private

  # Clean up test constants
  def cleanup_test_constants
    test_constants = [
      :BaseComponent, :Frontend, :Backend, :Database, :Application, :Deploy,
      :ExportTaskA, :ExportTaskB, :ExportTaskC,
      :TaskD, :TaskE, :TaskF,
      :CleanTaskA, :CleanTaskB,
      :RefTaskA, :RefTaskB, :RefDepTaskA, :RefDepTaskB,
      :SimpleTaskA, :SimpleTaskB,
      :StaticTaskA, :StaticTaskB,
      :CircularTaskA, :CircularTaskB, :ResetTaskA,
      :RefreshTaskA, :ErrorTaskA, :ExistingMethodTask, :OptionsTaskA,
      :ThreadSafeTask, :NestedTaskB, :BaseTaskA, :DerivedTaskA,
      :DeepTaskA, :DeepTaskB, :DeepTaskC, :DeepTaskD,
      :MultiExportTask, :ConcurrentTaskX, :ConcurrentTaskY,
      :BaseTask, :DependentTask, :DefineTask, :ExportsTask,
      :TimestampTask, :FailingIntegrationTask, :DependentIntegrationTask,
      :RecursionTaskA, :MonitorTask, :SharedTask,
      :OldService, :NewService, :DynamicTask,
      :IndependentTask, :MixedTask
    ]

    test_constants.each do |const|
      Object.send(:remove_const, const) if Object.const_defined?(const)
    end
  end
end
