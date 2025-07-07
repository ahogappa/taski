# frozen_string_literal: true

require "monitor"

# Load core components
require_relative "taski/version"
require_relative "taski/exceptions"
require_relative "taski/logger"
require_relative "taski/progress_display"
require_relative "taski/reference"
require_relative "taski/dependency_analyzer"
require_relative "taski/signal_handler"
require_relative "taski/tree_colors"
require_relative "taski/task_interface"
require_relative "taski/task_component"
require_relative "taski/instance_builder"
require_relative "taski/circular_dependency_detector"

# Load Task class components
require_relative "taski/task/base"
require_relative "taski/task/exports_api"
require_relative "taski/task/define_api"
require_relative "taski/task/instance_management"

# Load Section class
require_relative "taski/section"

module Taski
  # Main module for the Taski task framework
  #
  # Taski provides a framework for defining and managing task dependencies
  # with three complementary APIs:
  # 1. Exports API - Export instance variables as class methods (static dependencies)
  # 2. Define API - Define lazy-evaluated values with dynamic dependency resolution
  # 3. Section API - Abstraction layers with runtime implementation selection
  #
  # API Selection Guide:
  # - Use Exports API for simple static dependencies
  # - Use Define API for conditional dependencies analyzed at class definition time
  # - Use Section API for environment-specific implementations with static analysis
  #
  # Features:
  # - Automatic dependency resolution (static and dynamic)
  # - Static analysis of method dependencies
  # - Runtime implementation selection with Section API
  # - Thread-safe task building
  # - Circular dependency detection
  # - Memory leak prevention
end
