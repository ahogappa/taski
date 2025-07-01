# frozen_string_literal: true

require_relative "logging/formatter_factory"

module Taski
  # Enhanced logging functionality for Taski framework
  # Provides structured logging with multiple levels and context information
  class Logger
    # Log levels in order of severity
    LEVELS = {debug: 0, info: 1, warn: 2, error: 3}.freeze

    # @param level [Symbol] Minimum log level to output (:debug, :info, :warn, :error)
    # @param output [IO] Output destination (default: $stdout)
    # @param format [Symbol] Log format (:simple, :structured, :json)
    def initialize(level: :info, output: $stdout, format: :structured)
      @level = level
      @output = output
      @formatter = Logging::FormatterFactory.create(format)
      @start_time = Time.now
    end

    # Log debug message with optional context
    # @param message [String] Log message
    # @param context [Hash] Additional context information
    def debug(message, **context)
      log(:debug, message, context)
    end

    # Log info message with optional context
    # @param message [String] Log message
    # @param context [Hash] Additional context information
    def info(message, **context)
      log(:info, message, context)
    end

    # Log warning message with optional context
    # @param message [String] Log message
    # @param context [Hash] Additional context information
    def warn(message, **context)
      log(:warn, message, context)
    end

    # Log error message with optional context
    # @param message [String] Log message
    # @param context [Hash] Additional context information
    def error(message, **context)
      log(:error, message, context)
    end

    # Log task build start event
    # @param task_name [String] Name of the task being built
    # @param dependencies [Array] List of task dependencies
    # @param args [Hash] Build arguments for parametrized builds
    def task_build_start(task_name, dependencies: [], args: nil)
      context = {
        task: task_name,
        dependencies: dependencies.size,
        dependency_names: dependencies.map { |dep| dep.is_a?(Hash) ? dep[:klass].inspect : dep.inspect }
      }
      context[:args] = args if args && !args.empty?

      info("Task build started", **context)
    end

    # Log task build completion event
    # @param task_name [String] Name of the task that was built
    # @param duration [Float] Build duration in seconds
    def task_build_complete(task_name, duration: nil)
      context = {task: task_name}
      context[:duration_ms] = (duration * 1000).round(2) if duration
      info("Task build completed", **context)
    end

    # Log task build failure event
    # @param task_name [String] Name of the task that failed
    # @param error [Exception] The error that occurred
    # @param duration [Float] Duration before failure in seconds
    def task_build_failed(task_name, error:, duration: nil)
      context = {
        task: task_name,
        error_class: error.class.name,
        error_message: error.message
      }
      context[:duration_ms] = (duration * 1000).round(2) if duration
      context[:backtrace] = error.backtrace&.first(3) if error.backtrace
      error("Task build failed", **context)
    end

    # Log dependency resolution event
    # @param task_name [String] Name of the task resolving dependencies
    # @param resolved_count [Integer] Number of dependencies resolved
    def dependency_resolved(task_name, resolved_count:)
      debug("Dependencies resolved",
        task: task_name,
        resolved_dependencies: resolved_count)
    end

    # Log circular dependency detection
    # @param cycle_path [Array] The circular dependency path
    def circular_dependency_detected(cycle_path)
      error("Circular dependency detected",
        cycle: cycle_path.map { |klass| klass.name || klass.inspect },
        cycle_length: cycle_path.size)
    end

    private

    # Core logging method using Strategy Pattern
    # @param level [Symbol] Log level
    # @param message [String] Log message
    # @param context [Hash] Additional context
    def log(level, message, context)
      return unless should_log?(level)

      formatted_line = @formatter.format(level, message, context, @start_time)
      @output.puts formatted_line
    end

    # Check if message should be logged based on current level
    # @param level [Symbol] Message level to check
    # @return [Boolean] True if message should be logged
    def should_log?(level)
      LEVELS[@level] <= LEVELS[level]
    end
  end

  class << self
    # Get the current logger instance
    # @return [Logger] Current logger instance
    def logger
      @logger ||= Logger.new
    end

    # Get the current progress display instance (always enabled)
    # @return [ProgressDisplay] Current progress display instance
    def progress_display
      @progress_display ||= ProgressDisplay.new
    end

    # Configure the logger with new settings
    # @param level [Symbol] Log level (:debug, :info, :warn, :error)
    # @param output [IO] Output destination
    # @param format [Symbol] Log format (:simple, :structured, :json)
    def configure_logger(level: :info, output: $stdout, format: :structured)
      @logger = Logger.new(level: level, output: output, format: format)
    end

    # Set logger to quiet mode (only errors)
    def quiet!
      @logger = Logger.new(level: :error, output: @logger&.instance_variable_get(:@output) || $stdout)
    end

    # Set logger to verbose mode (all messages)
    def verbose!
      @logger = Logger.new(level: :debug, output: @logger&.instance_variable_get(:@output) || $stdout)
    end
  end
end
