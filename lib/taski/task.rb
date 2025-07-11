# frozen_string_literal: true

require_relative "exceptions"
require_relative "tree_display"
require_relative "task_interface"
require "monitor"

# Load all task modules
require_relative "task/core_constants"
require_relative "task/define_api"
require_relative "task/exports_api"
require_relative "task/instance_management"
require_relative "task/dependency_management"
require_relative "task/tree_display"

module Taski
  # Base Task class that provides the foundation for task framework
  # This class integrates multiple modules to provide full task functionality
  class Task
    extend Taski::TaskInterface::ClassMethods

    # Core modules
    include Task::CoreConstants

    # Class method modules
    extend Task::DefineAPI
    extend Task::ExportsAPI
    extend Task::InstanceManagement
    extend Task::DependencyManagement
    extend Task::TreeDisplay

    # === Instance Methods ===

    # Initialize task instance with optional run arguments
    # @param run_args [Hash, nil] Optional run arguments for parametrized execution
    def initialize(run_args = nil)
      @run_args = run_args
    end

    # Run method that must be implemented by subclasses
    # @raise [NotImplementedError] If not implemented by subclass
    def run
      raise NotImplementedError, "You must implement the run method in your task class"
    end

    # Build method for backward compatibility
    alias_method :build, :run

    # Access run arguments passed to parametrized runs
    # @return [Hash] Run arguments or empty hash if none provided
    def run_args
      @run_args || {}
    end

    # Build arguments alias for backward compatibility
    alias_method :build_args, :run_args

    # Clean method with default empty implementation
    # Subclasses can override this method to implement cleanup logic
    def clean
      # Default implementation does nothing - allows optional cleanup in subclasses
    end
  end
end
