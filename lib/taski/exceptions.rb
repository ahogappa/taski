# frozen_string_literal: true

module Taski
  # Custom exceptions for Taski framework

  # Raised when circular dependencies are detected between tasks
  class CircularDependencyError < StandardError; end

  # Raised when task analysis fails (e.g., constant resolution errors)
  class TaskAnalysisError < StandardError; end

  # Raised when task building fails during execution
  class TaskBuildError < StandardError; end

  # Raised when section implementation method is missing
  class SectionImplementationError < StandardError; end

  # Raised when task execution is interrupted by signal
  class TaskInterruptedException < StandardError; end
end
