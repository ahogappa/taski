# frozen_string_literal: true

module Taski
  # Base module for task-related components that need task class reference
  module TaskComponent
    # Initialize with task class
    # @param task_class [Class] The task class to hold reference to
    def initialize(task_class)
      @task_class = task_class
    end

    private

    attr_reader :task_class
  end
end
