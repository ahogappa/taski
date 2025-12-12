# frozen_string_literal: true

require_relative "taski/version"
require_relative "taski/static_analysis/analyzer"
require_relative "taski/static_analysis/visitor"
require_relative "taski/execution/registry"
require_relative "taski/execution/coordinator"
require_relative "taski/execution/task_wrapper"
require_relative "taski/execution/parallel_progress_display"
require_relative "taski/context"
require_relative "taski/task"
require_relative "taski/section"

module Taski
  # Main module for the Taski task execution framework
  #
  # Taski provides a framework for task execution with automatic
  # dependency resolution using static analysis.
  #
  # Features:
  # - Static dependency analysis using Prism AST
  # - Parallel execution of independent tasks
  # - Automatic dependency resolution
  # - Export mechanism for sharing values between tasks
  # - Section pattern for dynamic implementation selection
  #
  # Usage:
  #   class MyTask < Taski::Task
  #     exports :result
  #
  #     def run
  #       @result = "computed value"
  #     end
  #   end
  #
  #   MyTask.result  # Executes task and returns result

  # Exception raised when user wants to abort task execution
  class TaskAbortException < StandardError
  end

  # Global registry shared across all tasks
  #
  # @return [Execution::Registry] The global registry instance
  def self.global_registry
    @global_registry ||= Execution::Registry.new
  end

  # Reset the global registry
  def self.reset_global_registry!
    @global_registry = nil
  end

  # Global progress display for parallel execution
  #
  # @return [Execution::ParallelProgressDisplay, nil] The progress display instance or nil if disabled
  def self.progress_display
    return nil unless progress_enabled?
    @progress_display ||= Execution::ParallelProgressDisplay.new
  end

  # Check if progress display is enabled
  #
  # @return [Boolean] true if progress display is enabled
  def self.progress_enabled?
    ENV["TASKI_PROGRESS"] == "1" || ENV["TASKI_FORCE_PROGRESS"] == "1"
  end

  # Reset the progress display
  def self.reset_progress_display!
    @progress_display&.stop
    @progress_display = nil
  end
end
