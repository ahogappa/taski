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
require_relative "taski/execution/shared_state"
require_relative "taski/progress/layout/log"
require_relative "taski/progress/layout/simple"
require_relative "taski/progress/layout/tree"
require_relative "taski/args"
require_relative "taski/env"
require_relative "taski/logging"

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
    attr_reader :task_class, :error, :output_lines

    # @param task_class [Class] The task class that failed
    # @param error [Exception] The exception that was raised
    # @param output_lines [Array<String>] Recent output lines from the failed task
    def initialize(task_class:, error:, output_lines: [])
      @task_class = task_class
      @error = error
      @output_lines = output_lines
    end
  end

  # Mixin for exception classes to enable transparent rescue matching with AggregateError.
  # When extended by an exception class, `rescue ThatError` will also match
  # an AggregateError that contains ThatError.
  #
  # @note TaskError and all TaskClass::Error classes already extend this module.
  #
  # @example
  #   begin
  #     MyTask.value  # raises AggregateError containing MyTask::Error
  #   rescue MyTask::Error => e
  #     puts "MyTask failed: #{e.message}"
  #   end
  module AggregateAware
    def ===(other)
      return super unless other.is_a?(Taski::AggregateError)

      other.includes?(self)
    end
  end

  # Base class for task-specific error wrappers.
  # Each Task subclass automatically gets a ::Error class that inherits from this.
  # This allows rescuing errors by task class: rescue MyTask::Error => e
  #
  # @example Rescuing task-specific errors
  #   begin
  #     MyTask.value
  #   rescue MyTask::Error => e
  #     puts "MyTask failed: #{e.message}"
  #   end
  class TaskError < StandardError
    extend AggregateAware

    # @return [Exception] The original error that occurred in the task
    attr_reader :cause

    # @return [Class] The task class where the error occurred
    attr_reader :task_class

    # @param cause [Exception] The original error
    # @param task_class [Class] The task class where the error occurred
    def initialize(cause, task_class:)
      @cause = cause
      @task_class = task_class
      super(cause.message)
      set_backtrace(cause.backtrace)
    end
  end

  # Raised when multiple tasks fail during parallel execution
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

    # Check if this aggregate contains an error of the given type
    # @param exception_class [Class] The exception class to check for
    # @return [Boolean] true if any contained error is of the given type
    def includes?(exception_class)
      errors.any? { |f| f.error.is_a?(exception_class) }
    end

    private

    def build_message
      task_word = (errors.size == 1) ? "task" : "tasks"
      parts = ["#{errors.size} #{task_word} failed:"]

      errors.each do |f|
        parts << "  - #{f.task_class.name}: #{f.error.message}"

        # Include captured output if available
        if f.output_lines && !f.output_lines.empty?
          parts << "    Output:"
          f.output_lines.each { |line| parts << "      #{line}" }
        end
      end

      parts.join("\n")
    end
  end

  @args_monitor = Monitor.new
  @env_monitor = Monitor.new
  @message_monitor = Monitor.new
  @logger_monitor = Monitor.new

  # Get the current logger for structured logging
  # @return [Logger, nil] The configured logger or nil (disabled by default)
  def self.logger
    @logger_monitor.synchronize { @logger }
  end

  # Set the logger for structured logging
  # @param logger [Logger, nil] A Ruby Logger instance or nil to disable logging
  def self.logger=(logger)
    @logger_monitor.synchronize { @logger = logger }
  end

  # Get the current runtime arguments
  # @return [Args, nil] The current args or nil if no task is running
  def self.args
    @args_monitor.synchronize { @args }
  end

  # Get the current execution environment
  # @return [Env, nil] The current env or nil if no task is running
  def self.env
    @env_monitor.synchronize { @env }
  end

  # Output a message to the user without being captured by TaskOutputRouter.
  # During task execution with progress display, messages are queued and
  # displayed after execution completes. Without progress display or outside
  # task execution, messages are output immediately.
  #
  # @param text [String] The message text to display
  def self.message(text)
    @message_monitor.synchronize do
      progress = progress_display
      if progress&.respond_to?(:queue_message)
        progress.queue_message(text)
      else
        $stdout.puts(text)
      end
    end
  end

  # Start new execution environment (internal use only)
  # @api private
  # @return [Boolean] true if this call created the env, false if env already existed
  def self.start_env(root_task:)
    @env_monitor.synchronize do
      return false if @env
      @env = Env.new(root_task: root_task)
      true
    end
  end

  # Reset the execution environment (internal use only)
  # @api private
  def self.reset_env!
    @env_monitor.synchronize { @env = nil }
  end

  # Execute a block with env lifecycle management.
  # Creates env if it doesn't exist, and resets it only if this call created it.
  # This prevents race conditions in concurrent execution.
  #
  # @param root_task [Class] The root task class
  # @yield The block to execute with env available
  # @return [Object] The result of the block
  def self.with_env(root_task:)
    created_env = start_env(root_task: root_task)
    yield
  ensure
    reset_env! if created_env
  end

  # Start new runtime arguments (internal use only)
  # @api private
  # @return [Boolean] true if this call created the args, false if args already existed
  def self.start_args(options:)
    @args_monitor.synchronize do
      return false if @args
      @args = Args.new(options: options)
      true
    end
  end

  # Reset the runtime arguments (internal use only)
  # @api private
  def self.reset_args!
    @args_monitor.synchronize { @args = nil }
  end

  # Execute a block with args lifecycle management.
  # Creates args if they don't exist, and resets them only if this call created them.
  # This prevents race conditions in concurrent execution.
  #
  # @param options [Hash] User-defined options
  # @yield The block to execute with args available
  # @return [Object] The result of the block
  def self.with_args(options:)
    created_args = start_args(options: options)
    yield
  ensure
    reset_args! if created_args
  end

  # Progress display is enabled by default (tree-style).
  # Environment variables:
  # - TASKI_PROGRESS_DISABLE=1: Disable progress display entirely
  # - TASKI_PROGRESS_MODE=simple|tree: Set display mode (default: tree)
  def self.progress_display
    return nil if progress_disabled?
    @progress_display ||= create_progress_display
  end

  def self.progress_disabled?
    ENV["TASKI_PROGRESS_DISABLE"] == "1"
  end

  # Get the current progress mode (:tree or :simple)
  # Environment variable TASKI_PROGRESS_MODE takes precedence over code settings.
  # @return [Symbol] The current progress mode
  def self.progress_mode
    if ENV["TASKI_PROGRESS_MODE"]
      progress_mode_from_env
    else
      @progress_mode || :tree
    end
  end

  # Set the progress mode (:tree or :simple)
  # @param mode [Symbol] The mode to use (:tree or :simple)
  def self.progress_mode=(mode)
    @progress_mode = mode.to_sym
    # Reset display so it will be recreated with new mode
    @progress_display&.stop
    @progress_display = nil
  end

  def self.reset_progress_display!
    @progress_display&.stop
    @progress_display = nil
    @progress_mode = nil
  end

  # @api private
  def self.create_progress_display
    case progress_mode
    when :simple
      Progress::Layout::Simple.new
    when :log, :plain
      Progress::Layout::Log.new
    else
      Progress::Layout::Tree.new
    end
  end

  # @api private
  def self.progress_mode_from_env
    case ENV["TASKI_PROGRESS_MODE"]
    when "simple"
      :simple
    when "log", "plain"
      :log
    else
      :tree
    end
  end

  # Get the worker count from the current args (set via Task.run(workers: n))
  # @return [Integer, nil] The worker count or nil to use WorkerPool default
  # @api private
  def self.args_worker_count
    args&.fetch(:_workers, nil)
  end

  # Get the current registry for this thread (used during dependency resolution)
  # @return [Execution::Registry, nil] The current registry or nil
  # @api private
  def self.current_registry
    Thread.current[:taski_current_registry]
  end

  # Set the current registry for this thread (internal use only)
  # @api private
  def self.set_current_registry(registry)
    Thread.current[:taski_current_registry] = registry
  end

  # Clear the current registry for this thread (internal use only)
  # @api private
  def self.clear_current_registry
    Thread.current[:taski_current_registry] = nil
  end
end

# Load Task after Taski module is defined (it depends on TaskError)
require_relative "taski/task"
