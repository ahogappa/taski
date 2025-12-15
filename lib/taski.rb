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
  class TaskAbortException < StandardError
  end

  def self.global_registry
    @global_registry ||= Execution::Registry.new
  end

  def self.reset_global_registry!
    @global_registry = nil
  end

  def self.progress_display
    return nil unless progress_enabled?
    @progress_display ||= Execution::ParallelProgressDisplay.new
  end

  def self.progress_enabled?
    ENV["TASKI_PROGRESS"] == "1" || ENV["TASKI_FORCE_PROGRESS"] == "1"
  end

  def self.reset_progress_display!
    @progress_display&.stop
    @progress_display = nil
  end
end
