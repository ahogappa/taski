# frozen_string_literal: true

module Taski
  class Task
    # Core constants for task framework
    module CoreConstants
      # Constants for method tracking
      TASKI_ANALYZING_DEFINE_KEY = :taski_analyzing_define
      ANALYZED_METHODS = [:build, :clean, :run, :drop].freeze
    end
  end
end
