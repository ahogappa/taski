# frozen_string_literal: true

require_relative "../test_helper"

module Taski
  module TestHelper
    # Minitest integration module.
    # Include this in your test class for automatic mock cleanup.
    #
    # @example
    #   class MyTaskTest < Minitest::Test
    #     include Taski::TestHelper::Minitest
    #
    #     def test_something
    #       mock_task(FetchData, result: "mocked")
    #       # ... test code ...
    #     end
    #     # Mocks are automatically cleaned up after each test
    #   end
    module Minitest
      def self.included(base)
        base.include(Taski::TestHelper)
      end

      # Reset mocks before each test to ensure clean state.
      def setup
        super
        Taski::TestHelper.reset_mocks!
      end

      # Reset mocks after each test to prevent pollution.
      def teardown
        Taski::TestHelper.reset_mocks!
        super
      end
    end
  end
end
