# frozen_string_literal: true

module Taski
  module Logging
    # Interface for log formatters
    # All formatters must implement the format method
    module FormatterInterface
      # Format a log entry
      # @param level [Symbol] Log level (:debug, :info, :warn, :error)
      # @param message [String] Log message
      # @param context [Hash] Additional context information
      # @param start_time [Time] Logger start time for elapsed calculation
      # @return [String] Formatted log line
      def format(level, message, context, start_time)
        raise NotImplementedError, "Subclass must implement format method"
      end
    end
  end
end
