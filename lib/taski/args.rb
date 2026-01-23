# frozen_string_literal: true

require "monitor"

module Taski
  # Runtime arguments accessible from any task.
  # Holds user-defined options passed by the user at execution time.
  # Args is immutable after creation - options cannot be modified during task execution.
  class Args
    # @param options [Hash] User-defined options (immutable after creation)
    def initialize(options:)
      @options = options.dup.freeze
    end

    # Get a user-defined option value
    # @param key [Symbol, String] The option key
    # @return [Object, nil] The option value or nil if not set
    def [](key)
      @options[key]
    end

    # Get a user-defined option value with a default
    # @param key [Symbol, String] The option key
    # @param default [Object] Default value if key is not present
    # @yield Block to compute default value if key is not present
    # @return [Object] The option value or default
    def fetch(key, default = nil, &block)
      if @options.key?(key)
        @options[key]
      elsif block
        block.call
      else
        default
      end
    end

    # Check if a user-defined option key exists
    # @param key [Symbol, String] The option key
    # @return [Boolean] true if the key exists
    def key?(key)
      @options.key?(key)
    end
  end
end
