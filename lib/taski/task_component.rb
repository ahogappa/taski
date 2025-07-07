# frozen_string_literal: true

module Taski
  # Base module for task-related components that need task class reference and thread key generation
  # Also provides thread state management functionality
  module TaskComponent
    # Initialize with task class
    # @param task_class [Class] The task class to hold reference to
    def initialize(task_class)
      @task_class = task_class
    end

    # Execute block with thread build tracking
    # @yield Block to execute with build tracking enabled
    def with_build_tracking
      thread_key = build_thread_key
      Thread.current[thread_key] = true
      begin
        yield
      ensure
        Thread.current[thread_key] = false
      end
    end

    private

    attr_reader :task_class

    # Generate thread-local key for build tracking
    # @return [String] Thread key for this task's build state
    def build_thread_key
      "#{@task_class.name}#{Taski::Task::THREAD_KEY_SUFFIX}"
    end
  end
end
