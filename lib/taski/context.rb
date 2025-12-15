# frozen_string_literal: true

require "monitor"

module Taski
  # Runtime context accessible from any task.
  # Holds user-defined options and execution metadata.
  # Context is immutable after creation - options cannot be modified during task execution.
  class Context
    attr_reader :started_at, :working_directory, :root_task

    # @param options [Hash] User-defined options (immutable after creation)
    # @param root_task [Class] The root task class that initiated execution
    def initialize(options:, root_task:)
      @options = options.dup.freeze
      @root_task = root_task
      @started_at = Time.now
      @working_directory = Dir.pwd
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
