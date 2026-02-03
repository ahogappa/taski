# frozen_string_literal: true

require_relative "base"

module Taski
  module Execution
    module Template
      # Default template for Plain Layout.
      # Uses the base implementation without modifications.
      #
      # This is the default template used when no custom template is provided.
      # It outputs plain text with simple prefixes like [START], [DONE], [FAIL].
      class Default < Base
        # Default implementation inherits all methods from Base.
        # Override specific methods here if needed.
      end
    end
  end
end
