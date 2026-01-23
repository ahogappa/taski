# frozen_string_literal: true

module Taski
  module TestHelper
    # Global registry that stores mock definitions for tests.
    # Uses a Mutex for thread-safety when accessed from worker threads.
    # Mocks should be reset in test setup/teardown to ensure test isolation.
    module MockRegistry
      @mutex = Mutex.new
      @mocks = {}

      class << self
        # Registers a mock for a task class.
        # If a mock already exists for this class, it is replaced.
        # @param task_class [Class] The task class to mock
        # @param mock_wrapper [MockWrapper] The mock wrapper instance
        def register(task_class, mock_wrapper)
          @mutex.synchronize do
            @mocks[task_class] = mock_wrapper
          end
        end

        # Retrieves the mock wrapper for a task class, if one exists.
        # @param task_class [Class] The task class to look up
        # @return [MockWrapper, nil] The mock wrapper or nil if not mocked
        def mock_for(task_class)
          @mutex.synchronize do
            @mocks[task_class]
          end
        end

        # Checks if any mocks are registered.
        # Used for optimization to skip mock lookup in hot paths.
        # @return [Boolean] true if mocks exist
        def mocks_active?
          @mutex.synchronize do
            !@mocks.empty?
          end
        end

        # Clears all registered mocks and resets args/env.
        # Should be called in test setup/teardown.
        def reset!
          @mutex.synchronize do
            @mocks = {}
          end
          Taski.reset_args!
          Taski.reset_env!
        end
      end
    end
  end
end
