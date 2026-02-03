# frozen_string_literal: true

require_relative "base"

module Taski
  module Execution
    module Layout
      # Plain layout for non-TTY environments (CI, log files, piped output).
      # Outputs plain text without terminal escape codes.
      #
      # Output format:
      #   [START] TaskName
      #   [DONE] TaskName (123.4ms)
      #   [FAIL] TaskName: Error message
      #
      # This replaces the old PlainProgressDisplay class.
      class Plain < Base
        def initialize(output: $stderr, template: nil)
          super
          @output.sync = true if @output.respond_to?(:sync=)
        end
      end
    end
  end
end
