# frozen_string_literal: true

require_relative "taski/version"
require_relative "taski/static_analysis/analyzer"
require_relative "taski/static_analysis/visitor"
require_relative "taski/static_analysis/dependency_graph"
require_relative "taski/execution/registry"
require_relative "taski/execution/task_wrapper"
require_relative "taski/execution/executor"
require_relative "taski/execution/parallel_progress_display"
require_relative "taski/context"
require_relative "taski/task"
require_relative "taski/section"

module Taski
  class TaskAbortException < StandardError
  end

  # Raised when circular dependencies are detected between tasks
  class CircularDependencyError < StandardError
    attr_reader :cyclic_tasks

    # @param cyclic_tasks [Array<Array<Class>>] Groups of mutually dependent task classes
    def initialize(cyclic_tasks)
      @cyclic_tasks = cyclic_tasks
      task_names = cyclic_tasks.map { |group| group.map(&:name).join(" <-> ") }.join(", ")
      super("Circular dependency detected: #{task_names}")
    end
  end

  @context_monitor = Monitor.new

  # Get the current execution context
  # @return [Context, nil] The current context or nil if no task is running
  def self.context
    @context_monitor.synchronize { @context }
  end

  # Start a new execution context (internal use only)
  # @api private
  def self.start_context(options:, root_task:)
    @context_monitor.synchronize do
      return if @context
      @context = Context.new(options: options, root_task: root_task)
    end
  end

  # Reset the execution context (internal use only)
  # @api private
  def self.reset_context!
    @context_monitor.synchronize { @context = nil }
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
