# frozen_string_literal: true

module Taski
  module Execution
    module ProgressFeatures
      # Provides progress state tracking for tasks.
      # Include this module to track task states and get progress summaries.
      #
      # @example
      #   class MyDisplay
      #     include ProgressFeatures::ProgressTracking
      #
      #     def initialize
      #       init_progress_tracking
      #     end
      #
      #     def handle_task_start(task_class)
      #       register_task(task_class)
      #       update_task_state(task_class, :running, nil, nil)
      #     end
      #   end
      module ProgressTracking
        # Simple task state container
        class TaskState
          attr_accessor :state, :duration, :error, :start_time

          def initialize
            @state = :pending
            @duration = nil
            @error = nil
            @start_time = nil
          end
        end

        # Initialize the progress tracking state.
        # Must be called in the including class's initialize method.
        def init_progress_tracking
          @tracked_tasks = {}
        end

        # Register a task for tracking.
        # @param task_class [Class] The task class to track
        def register_task(task_class)
          @tracked_tasks ||= {}
          return if @tracked_tasks.key?(task_class)
          @tracked_tasks[task_class] = TaskState.new
        end

        # Update the state of a tracked task.
        # @param task_class [Class] The task class
        # @param state [Symbol] New state (:pending, :running, :completed, :failed)
        # @param duration [Float, nil] Duration in milliseconds (for completed)
        # @param error [Exception, nil] Error object (for failed)
        def update_task_state(task_class, state, duration, error)
          @tracked_tasks ||= {}
          task_state = @tracked_tasks[task_class] || TaskState.new
          task_state.state = state
          task_state.duration = duration
          task_state.error = error
          task_state.start_time = Time.now if state == :running
          @tracked_tasks[task_class] = task_state
        end

        # Get the current state of a task.
        # @param task_class [Class] The task class
        # @return [Symbol, nil] Current state or nil if not tracked
        def task_state(task_class)
          @tracked_tasks ||= {}
          @tracked_tasks[task_class]&.state
        end

        # Get the count of completed tasks.
        # @return [Integer] Number of completed tasks
        def completed_count
          @tracked_tasks ||= {}
          @tracked_tasks.values.count { |t| t.state == :completed }
        end

        # Get the total count of tracked tasks.
        # @return [Integer] Total number of tasks
        def total_count
          @tracked_tasks ||= {}
          @tracked_tasks.size
        end

        # Get the list of currently running tasks.
        # @return [Array<Class>] Array of running task classes
        def running_tasks
          @tracked_tasks ||= {}
          @tracked_tasks.select { |_, t| t.state == :running }.keys
        end

        # Get a summary of progress.
        # @return [Hash] Summary with :completed, :total, :running, :failed
        def progress_summary
          @tracked_tasks ||= {}
          {
            completed: @tracked_tasks.values.count { |t| t.state == :completed },
            total: @tracked_tasks.size,
            running: @tracked_tasks.select { |_, t| t.state == :running }.keys,
            failed: @tracked_tasks.select { |_, t| t.state == :failed }.keys
          }
        end
      end
    end
  end
end
