# frozen_string_literal: true

require_relative "taski/version"
require_relative "taski/static_analysis/analyzer"
require_relative "taski/static_analysis/visitor"
require_relative "taski/static_analysis/dependency_graph"
require_relative "taski/execution/registry"
require_relative "taski/execution/execution_context"
require_relative "taski/execution/task_wrapper"
require_relative "taski/execution/scheduler"
require_relative "taski/execution/worker_pool"
require_relative "taski/execution/executor"
require_relative "taski/execution/tree_progress_display"
require_relative "taski/args"
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

  # Represents a single task failure with its context
  class TaskFailure
    attr_reader :task_class, :error

    # @param task_class [Class] The task class that failed
    # @param error [Exception] The exception that was raised
    def initialize(task_class:, error:)
      @task_class = task_class
      @error = error
    end
  end

  # Raised when multiple tasks fail during parallel execution
  # Provides Go-style error inspection via includes? and find methods
  class AggregateError < StandardError
    attr_reader :errors

    # @param errors [Array<TaskFailure>] List of task failures
    def initialize(errors)
      @errors = errors
      super(build_message)
    end

    # Returns the first error for compatibility with exception chaining
    # @return [Exception, nil] The first error or nil if no errors
    def cause
      errors.first&.error
    end

    # Check if this aggregate contains an error of the given type (like Go's errors.Is)
    # @param exception_class [Class] The exception class to check for
    # @return [Boolean] true if any contained error is of the given type
    def includes?(exception_class)
      errors.any? { |f| f.error.is_a?(exception_class) }
    end

    # Find the first error of the given type (like Go's errors.As)
    # @param exception_class [Class] The exception class to find
    # @return [Exception, nil] The first matching error or nil
    def find(exception_class)
      failure = errors.find { |f| f.error.is_a?(exception_class) }
      failure&.error
    end

    private

    def build_message
      "#{errors.size} tasks failed:\n" +
        errors.map { |f| "  - #{f.task_class.name}: #{f.error.message}" }.join("\n")
    end
  end

  @args_monitor = Monitor.new

  # Get the current runtime arguments
  # @return [Args, nil] The current args or nil if no task is running
  def self.args
    @args_monitor.synchronize { @args }
  end

  # Start new runtime arguments (internal use only)
  # @api private
  def self.start_args(options:, root_task:)
    @args_monitor.synchronize do
      return if @args
      @args = Args.new(options: options, root_task: root_task)
    end
  end

  # Reset the runtime arguments (internal use only)
  # @api private
  def self.reset_args!
    @args_monitor.synchronize { @args = nil }
  end

  def self.global_registry
    @global_registry ||= Execution::Registry.new
  end

  def self.reset_global_registry!
    @global_registry = nil
  end

  # Progress display is enabled by default (tree-style).
  # Environment variables:
  # - TASKI_PROGRESS_DISABLE=1: Disable progress display entirely
  def self.progress_display
    return nil if progress_disabled?
    @progress_display ||= Execution::TreeProgressDisplay.new
  end

  def self.progress_disabled?
    ENV["TASKI_PROGRESS_DISABLE"] == "1"
  end

  def self.reset_progress_display!
    @progress_display&.stop
    @progress_display = nil
  end

  # Get the worker count from the current args (set via Task.run(workers: n))
  # @return [Integer, nil] The worker count or nil to use WorkerPool default
  # @api private
  def self.args_worker_count
    args&.fetch(:_workers, nil)
  end
end
