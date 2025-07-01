# frozen_string_literal: true

require_relative "formatter_interface"

module Taski
  module Logging
    # Simple log formatter: [LEVEL] message
    class SimpleFormatter
      include FormatterInterface

      def format(level, message, context, start_time)
        "[#{level.upcase}] #{message}"
      end
    end
  end
end
