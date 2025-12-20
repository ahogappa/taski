# frozen_string_literal: true

module Taski
  module Execution
    # Scheduler manages task dependency state and determines execution order.
    # It tracks which tasks are pending, enqueued, or completed, and provides
    # methods to determine which tasks are ready to execute.
    #
    # Thread Safety: Scheduler is only accessed from the main thread in Executor,
    # so no synchronization is needed.
    class Scheduler
      # Task execution states
      STATE_PENDING = :pending
      STATE_ENQUEUED = :enqueued
      STATE_COMPLETED = :completed

      def initialize
        @dependencies = {}
        @task_states = {}
        @completed_tasks = Set.new
      end

      # Build dependency graph by traversing from root task.
      # Populates internal state with all tasks and their dependencies.
      #
      # @param root_task_class [Class] The root task class to start from
      def build_dependency_graph(root_task_class)
        # @type var queue: Array[singleton(Taski::Task)]
        queue = [root_task_class]

        while (task_class = queue.shift)
          next if @task_states.key?(task_class)

          deps = task_class.cached_dependencies
          @dependencies[task_class] = deps.dup
          @task_states[task_class] = STATE_PENDING

          deps.each { |dep| queue << dep }
        end
      end

      # Get all tasks that are ready to execute.
      # A task is ready when all its dependencies are completed.
      #
      # @return [Array<Class>] Array of task classes ready for execution
      def next_ready_tasks
        ready = []
        @task_states.each_key do |task_class|
          next unless @task_states[task_class] == STATE_PENDING
          next unless ready_to_execute?(task_class)
          ready << task_class
        end
        ready
      end

      # Mark a task as enqueued for execution.
      #
      # @param task_class [Class] The task class to mark
      def mark_enqueued(task_class)
        @task_states[task_class] = STATE_ENQUEUED
      end

      # Mark a task as completed.
      #
      # @param task_class [Class] The task class to mark
      def mark_completed(task_class)
        @task_states[task_class] = STATE_COMPLETED
        @completed_tasks.add(task_class)
      end

      # Check if a task is completed.
      #
      # @param task_class [Class] The task class to check
      # @return [Boolean] true if the task is completed
      def completed?(task_class)
        @completed_tasks.include?(task_class)
      end

      # Check if there are any running (enqueued) tasks.
      #
      # @return [Boolean] true if there are tasks currently running
      def running_tasks?
        @task_states.values.any? { |state| state == STATE_ENQUEUED }
      end

      private

      # Check if a task is ready to execute (all dependencies completed).
      #
      # @param task_class [Class] The task class to check
      # @return [Boolean] true if the task is ready
      def ready_to_execute?(task_class)
        task_deps = @dependencies[task_class] || Set.new
        task_deps.subset?(@completed_tasks)
      end
    end
  end
end
