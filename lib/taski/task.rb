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
    include Taski::TaskInterface::InstanceMethods

    # Core modules
    include Task::CoreConstants

    # Class method modules
    extend Task::DefineAPI
    extend Task::ExportsAPI
    extend Task::InstanceManagement
    extend Task::DependencyManagement
    extend Task::TreeDisplay

    # Instance method delegation for ref()
    # Enable ref() as instance method by delegating to class method
    def ref(klass_name)
      self.class.ref(klass_name)
    end

    # === Instance Methods ===

    # Initialize task instance with optional run arguments
    # @param run_args [Hash, nil] Optional run arguments for parametrized execution
    def initialize(run_args = nil)
      @run_args = run_args
    end

    # Access run arguments passed to parametrized runs
    # @return [Hash] Run arguments or empty hash if none provided
    def run_args
      @run_args || {}
    end

    # Build arguments alias for backward compatibility
    alias_method :build_args, :run_args
  end
end
