# frozen_string_literal: true

require_relative "base"
require_relative "../theme/plain"

module Taski
  module Progress
    module Layout
      # Log layout for non-TTY environments (CI, log files, piped output).
      # Outputs plain text without terminal escape codes.
      #
      # Output format:
      #   [START] TaskName
      #   [DONE] TaskName (123.4ms)
      #   [FAIL] TaskName: Error message
      #
      # Uses Theme::Plain by default to ensure no ANSI escape codes in output.
      module Log
        # Build the plain-text display (Log has a single implementation).
        # @return [Log::Display]
        def self.build(output: $stderr, theme: nil)
          Display.new(output: output, theme: theme)
        end

        class Display < Base
          def initialize(output: $stderr, theme: nil)
            theme ||= Theme::Plain.new
            super
            @output.sync = true if @output.respond_to?(:sync=)
          end
        end
      end
    end
  end
end
