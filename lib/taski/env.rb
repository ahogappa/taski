# frozen_string_literal: true

module Taski
  # Runtime execution environment information.
  # Holds system-managed metadata that is set automatically during task execution.
  # Env is immutable after creation.
  class Env
    attr_reader :root_task, :started_at, :working_directory

    # @param root_task [Class] The root task class that initiated execution
    def initialize(root_task:)
      @root_task = root_task
      @started_at = Time.now
      @working_directory = Dir.pwd
    end
  end
end
