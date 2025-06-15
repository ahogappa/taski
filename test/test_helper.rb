# frozen_string_literal: true

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

    # Reset task instances
    if Taski::Task.instance_variable_defined?(:@__task_instances)
      Taski::Task.remove_instance_variable(:@__task_instances)
    end

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
      :OldService, :NewService, :DynamicTask
    ]

    test_constants.each do |const|
      Object.send(:remove_const, const) if Object.const_defined?(const)
    end
  end
end