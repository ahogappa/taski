# frozen_string_literal: true

module Taski
  # Custom exceptions for Taski framework

  # Raised when circular dependencies are detected between tasks
  class CircularDependencyError < StandardError; end

  # Raised when task analysis fails (e.g., constant resolution errors)
  class TaskAnalysisError < StandardError; end

  # Raised when task building fails during execution
  class TaskBuildError < StandardError; end
end
