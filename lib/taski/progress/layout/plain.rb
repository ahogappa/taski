# frozen_string_literal: true

require_relative "base"
require_relative "../template/plain"

module Taski
  module Progress
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
      # Uses Template::Plain by default to ensure no ANSI escape codes in output.
      class Plain < Base
        def initialize(output: $stderr, template: nil)
          template ||= Template::Plain.new
          super
          @output.sync = true if @output.respond_to?(:sync=)
        end
      end
    end
  end
end
