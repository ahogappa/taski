# frozen_string_literal: true

require "set"
require "monitor"

# Load core components
require_relative "taski/version"
require_relative "taski/exceptions"
require_relative "taski/reference"
require_relative "taski/dependency_analyzer"

# Load Task class components
require_relative "taski/task/base"
require_relative "taski/task/exports_api"
require_relative "taski/task/define_api"
require_relative "taski/task/instance_management"
require_relative "taski/task/dependency_resolver"

module Taski
  # Main module for the Taski task framework
  #
  # Taski provides a framework for defining and managing task dependencies
  # with two complementary APIs:
  # 1. Exports API - Export instance variables as class methods (static dependencies)
  # 2. Define API - Define lazy-evaluated values with dynamic dependency resolution
  #
  # Use Define API when:
  # - Dependencies change based on runtime conditions
  # - Environment-specific configurations
  # - Feature flags determine which classes to use
  # - Complex conditional logic determines dependencies
  #
  # Features:
  # - Automatic dependency resolution (static and dynamic)
  # - Static analysis of method dependencies
  # - Runtime dependency resolution for conditional logic
  # - Thread-safe task building
  # - Circular dependency detection
  # - Memory leak prevention
end
