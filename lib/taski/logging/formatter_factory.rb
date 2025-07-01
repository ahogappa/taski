# frozen_string_literal: true

require_relative "simple_formatter"
require_relative "structured_formatter"
require_relative "json_formatter"

module Taski
  module Logging
    # Factory for creating log formatters
    class FormatterFactory
      # Create a formatter instance based on format symbol
      # @param format [Symbol] Format type (:simple, :structured, :json)
      # @return [FormatterInterface] Formatter instance
      def self.create(format)
        case format
        when :simple
          SimpleFormatter.new
        when :structured
          StructuredFormatter.new
        when :json
          JsonFormatter.new
        else
          raise ArgumentError, "Unknown format: #{format}. Valid formats: :simple, :structured, :json"
        end
      end

      # Get list of available formats
      # @return [Array<Symbol>] Available format symbols
      def self.available_formats
        [:simple, :structured, :json]
      end
    end
  end
end
