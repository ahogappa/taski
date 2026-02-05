# frozen_string_literal: true

require_relative "../test_helper"

module Taski
  module TestHelper
    # RSpec integration module.
    # Include this in your RSpec examples for automatic mock cleanup.
    #
    # @example In spec_helper.rb
    #   require 'taski/test_helper/rspec'
    #
    #   RSpec.configure do |config|
    #     config.include Taski::TestHelper::RSpec
    #   end
    #
    # @example In individual specs
    #   RSpec.describe MyTask do
    #     include Taski::TestHelper::RSpec
    #
    #     it "processes data" do
    #       mock_task(FetchData, result: "mocked")
    #       # ... test code ...
    #     end
    #   end
    module RSpec
      def self.included(base)
        base.include(Taski::TestHelper)

        # Add before/after hooks when included in RSpec
        return unless base.respond_to?(:before) && base.respond_to?(:after)

        base.before(:each) { Taski::TestHelper.reset_mocks! }
        base.after(:each) { Taski::TestHelper.reset_mocks! }
      end
    end
  end
end
