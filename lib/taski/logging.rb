# frozen_string_literal: true

require "json"
require "monitor"
require "time"
require_relative "logging/logger_observer"

module Taski
  # Logging module provides structured logging support for debugging and monitoring.
  # Logging is disabled by default and has zero overhead when not configured.
  #
  # @example Basic setup
  #   require 'logger'
  #   Taski.logger = Logger.new($stderr, level: Logger::INFO)
  #
  # @example JSON output for monitoring systems
  #   Taski.logger = Logger.new('/var/log/taski.log')
  module Logging
    # Event type constants
    module Events
      EXECUTION_STARTED = "execution.started"
      EXECUTION_COMPLETED = "execution.completed"
      TASK_STARTED = "task.started"
      TASK_COMPLETED = "task.completed"
      TASK_FAILED = "task.failed"
      TASK_SKIPPED = "task.skipped"
      TASK_CLEAN_STARTED = "task.clean_started"
      TASK_CLEAN_COMPLETED = "task.clean_completed"
      TASK_CLEAN_FAILED = "task.clean_failed"
      DEPENDENCY_RESOLVED = "dependency.resolved"
    end

    # Log severity levels matching Ruby Logger
    module Levels
      DEBUG = 0
      INFO = 1
      WARN = 2
      ERROR = 3
    end

    class << self
      # Log a structured event. No-op if logger is nil.
      #
      # @param level [Integer] Log level (DEBUG, INFO, WARN, ERROR)
      # @param event [String] Event type constant
      # @param task [String, nil] Task class name
      # @param data [Hash] Additional event data
      def log(level, event, task: nil, **data)
        logger = Taski.logger
        return unless logger

        entry = build_entry(event, task, data)
        message = entry.to_json

        case level
        when Levels::DEBUG
          logger.debug(message)
        when Levels::INFO
          logger.info(message)
        when Levels::WARN
          logger.warn(message)
        when Levels::ERROR
          logger.error(message)
        end
      end

      # Convenience methods for each log level
      def debug(event, **kwargs) = log(Levels::DEBUG, event, **kwargs)
      def info(event, **kwargs) = log(Levels::INFO, event, **kwargs)
      def warn(event, **kwargs) = log(Levels::WARN, event, **kwargs)
      def error(event, **kwargs) = log(Levels::ERROR, event, **kwargs)

      private

      def build_entry(event, task, data)
        entry = {
          timestamp: Time.now.utc.iso8601(3),
          event: event,
          thread_id: Thread.current.object_id
        }
        entry[:task] = task if task
        entry[:data] = data unless data.empty?
        entry
      end
    end
  end
end
