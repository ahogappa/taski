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
      # This replaces the old PlainProgressDisplay class.
      # Uses Theme::Plain by default to ensure no ANSI escape codes in output.
      class Log < Base
        def initialize(output: $stderr, theme: nil)
          theme ||= Theme::Plain.new
          super
          @output.sync = true if @output.respond_to?(:sync=)
        end
      end
    end
  end
end
