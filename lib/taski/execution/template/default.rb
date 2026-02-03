# frozen_string_literal: true

require_relative "base"

module Taski
  module Execution
    module Template
      # Default template with minimal styling.
      # Outputs plain text without terminal escape codes or colors.
      #
      # This is the default template used when no custom template is provided.
      # Suitable for non-TTY environments (CI, log files, piped output).
      #
      # Output format:
      #   [START] TaskName
      #   [DONE] TaskName (123ms)
      #   [FAIL] TaskName: Error message
      class Default < Base
        # Inherits all methods from Base with plain defaults.
      end
    end
  end
end
