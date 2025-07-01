# frozen_string_literal: true

module Taski
  module Progress
    # Represents task execution status
    class TaskStatus
      attr_reader :name, :duration, :error

      def initialize(name:, duration: nil, error: nil)
        @name = name
        @duration = duration
        @error = error
      end

      def success?
        @error.nil?
      end

      def failure?
        !success?
      end

      def duration_ms
        return nil unless @duration
        (@duration * 1000).round(1)
      end

      def icon
        success? ? "✅" : "❌"
      end

      def format_duration
        return "" unless duration_ms
        "(#{duration_ms}ms)"
      end
    end
  end
end
