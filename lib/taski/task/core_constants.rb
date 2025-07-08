# frozen_string_literal: true

module Taski
  class Task
    # Core constants and thread-local keys for task framework
    module CoreConstants
      # Constants for thread-local keys and method tracking
      THREAD_KEY_SUFFIX = "_building"
      TASKI_ANALYZING_DEFINE_KEY = :taski_analyzing_define
      TASKI_CURRENT_PARENT_TASK_KEY = :taski_current_parent_task
      ANALYZED_METHODS = [:build, :clean, :run].freeze
    end
  end
end
