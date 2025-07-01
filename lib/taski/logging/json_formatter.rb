# frozen_string_literal: true

require_relative "formatter_interface"

module Taski
  module Logging
    # JSON log formatter for structured logging systems
    class JsonFormatter
      include FormatterInterface

      def format(level, message, context, start_time)
        require "json"

        log_entry = {
          timestamp: Time.now.iso8601(3),
          level: level.to_s,
          logger: "taski",
          message: message,
          elapsed_ms: ((Time.now - start_time) * 1000).round(1)
        }.merge(context)

        JSON.generate(log_entry)
      end
    end
  end
end
