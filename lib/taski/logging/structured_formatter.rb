# frozen_string_literal: true

require_relative "formatter_interface"

module Taski
  module Logging
    # Structured log formatter with timestamp and context
    class StructuredFormatter
      include FormatterInterface

      def format(level, message, context, start_time)
        timestamp = Time.now.strftime("%Y-%m-%d %H:%M:%S.%3N")
        elapsed = ((Time.now - start_time) * 1000).round(1)

        line = "[#{timestamp}] [#{elapsed}ms] #{level.to_s.upcase.ljust(5)} Taski: #{message}"

        unless context.empty?
          context_parts = context.map do |key, value|
            "#{key}=#{format_value(value)}"
          end
          line += " (#{context_parts.join(", ")})"
        end

        line
      end

      private

      # Format values for structured logging
      def format_value(value)
        case value
        when String
          (value.length > 50) ? "#{value[0..47]}..." : value
        when Array
          (value.size > 5) ? "[#{value[0..4].join(", ")}, ...]" : value.inspect
        when Hash
          (value.size > 3) ? "{#{value.keys[0..2].join(", ")}, ...}" : value.inspect
        else
          value.inspect
        end
      end
    end
  end
end
