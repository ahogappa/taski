# frozen_string_literal: true

module Taski
  module TestHelper
    # Wraps a mocked task and returns pre-configured values without executing the task.
    # Tracks which methods were accessed for verification in tests.
    class MockWrapper
      attr_reader :task_class, :mock_values

      # @param task_class [Class] The task class being mocked
      # @param mock_values [Hash{Symbol => Object}] Method names mapped to their return values
      def initialize(task_class, mock_values)
        @task_class = task_class
        @mock_values = mock_values
        @access_counts = Hash.new(0)
      end

      # Returns the mocked value for a method and records the access.
      # @param method_name [Symbol] The exported method name
      # @return [Object] The pre-configured mock value
      # @raise [KeyError] If method_name was not configured in the mock
      def get_exported_value(method_name)
        unless @mock_values.key?(method_name)
          raise KeyError, "No mock value for method :#{method_name} on #{@task_class}"
        end

        @access_counts[method_name] += 1
        @mock_values[method_name]
      end

      # Checks if a method was accessed at least once.
      # @param method_name [Symbol] The method name to check
      # @return [Boolean] true if accessed at least once
      def accessed?(method_name)
        @access_counts[method_name] > 0
      end

      # Returns the number of times a method was accessed.
      # @param method_name [Symbol] The method name to check
      # @return [Integer] Number of accesses (0 if never accessed)
      def access_count(method_name)
        @access_counts[method_name]
      end
    end
  end
end
