# frozen_string_literal: true

require "monitor"

module Taski
  # Runtime context accessible from any task (not included in dependency analysis).
  class Context
    @monitor = Monitor.new

    class << self
      # @return [String] The working directory path
      def working_directory
        @monitor.synchronize do
          @working_directory ||= Dir.pwd
        end
      end

      # @return [Time] The start time
      def started_at
        @monitor.synchronize do
          @started_at ||= Time.now
        end
      end

      # @return [Class, nil] The root task class or nil if not set
      def root_task
        @monitor.synchronize do
          @root_task
        end
      end

      # Called internally when a task is first invoked. Only the first call has effect.
      # @param task_class [Class] The task class to set as root
      def set_root_task(task_class)
        @monitor.synchronize do
          return if @root_task
          @root_task = task_class
          @started_at ||= Time.now
          @working_directory ||= Dir.pwd
        end
      end

      def reset!
        @monitor.synchronize do
          @working_directory = nil
          @started_at = nil
          @root_task = nil
        end
      end
    end
  end
end
