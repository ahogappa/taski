# frozen_string_literal: true

require "monitor"

module Taski
  # Provides runtime context information accessible from any task.
  # Unlike regular tasks, Context is not included in dependency analysis.
  #
  # Usage:
  #   class MyTask < Taski::Task
  #     def run
  #       puts "Working directory: #{Taski::Context.working_directory}"
  #       puts "Started at: #{Taski::Context.started_at}"
  #       puts "Root task: #{Taski::Context.root_task}"
  #     end
  #   end
  class Context
    @monitor = Monitor.new

    class << self
      # Get the working directory where task execution started
      #
      # @return [String] The working directory path
      def working_directory
        @monitor.synchronize do
          @working_directory ||= Dir.pwd
        end
      end

      # Get the time when task execution started
      #
      # @return [Time] The start time
      def started_at
        @monitor.synchronize do
          @started_at ||= Time.now
        end
      end

      # Get the root task class (the first task that was called)
      #
      # @return [Class, nil] The root task class or nil if not set
      def root_task
        @monitor.synchronize do
          @root_task
        end
      end

      # Set the root task class (only the first call has effect)
      # This method is called internally when a task is first invoked.
      #
      # @param task_class [Class] The task class to set as root
      def set_root_task(task_class)
        @monitor.synchronize do
          return if @root_task
          @root_task = task_class
          # Initialize started_at and working_directory when root task is set
          @started_at ||= Time.now
          @working_directory ||= Dir.pwd
        end
      end

      # Reset all context values
      # This is called when Taski::Task.reset! is invoked.
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
