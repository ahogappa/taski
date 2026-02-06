# frozen_string_literal: true

module Taski
  module Execution
    # Scheduler manages task dependency state and determines execution order.
    # It tracks which tasks are pending, enqueued, or completed, and provides
    # methods to determine which tasks are ready to execute.
    #
    # == Responsibilities
    #
    # - Build dependency graph from root task via static analysis
    # - Track task states: pending, enqueued, completed
    # - Determine which tasks are ready to execute (all dependencies completed)
    # - Provide next_ready_tasks for the Executor's event loop
    # - Build reverse dependency graph for clean operations
    # - Track clean states independently from run states
    # - Provide next_ready_clean_tasks for reverse dependency order execution
    #
    # == API
    #
    # Run operations:
    # - {#build_dependency_graph} - Initialize dependency graph from root task
    # - {#next_ready_tasks} - Get tasks ready for execution
    # - {#mark_enqueued} - Mark task as sent to worker pool
    # - {#mark_completed} - Mark task as finished
    # - {#completed?} - Check if task is completed
    # - {#running_tasks?} - Check if any tasks are currently executing
    #
    # Clean operations:
    # - {#build_reverse_dependency_graph} - Build reverse graph for clean order
    # - {#next_ready_clean_tasks} - Get tasks ready for clean (reverse order)
    # - {#mark_clean_enqueued} - Mark task as sent for clean
    # - {#mark_clean_completed} - Mark task as clean finished
    # - {#clean_completed?} - Check if task clean is completed
    # - {#running_clean_tasks?} - Check if any clean tasks are currently executing
    #
    # == Thread Safety
    #
    # Scheduler is only accessed from the main thread in Executor,
    # so no synchronization is needed. The Executor serializes all
    # access to the Scheduler through its event loop.
    class Scheduler
      # Task execution states
      STATE_PENDING = :pending
      STATE_ENQUEUED = :enqueued
      STATE_COMPLETED = :completed

      # Clean execution states (independent from run states)
      CLEAN_STATE_PENDING = :clean_pending
      CLEAN_STATE_ENQUEUED = :clean_enqueued
      CLEAN_STATE_COMPLETED = :clean_completed

      ##
      # Initializes internal data structures used to track normal and clean task execution.
      #
      # Sets up:
      # - @dependencies: map from task class to its dependency task classes.
      # - @task_states: map from task class to its normal execution state.
      # - @completed_tasks: set of task classes that have completed normal execution.
      # - @reverse_dependencies: map from task class to dependent task classes (used for clean ordering).
      # - @clean_task_states: map from task class to its clean execution state.
      # - @clean_completed_tasks: set of task classes that have completed clean execution.
      def initialize
        # Run execution state
        @dependencies = {}
        @task_states = {}
        @completed_tasks = Set.new

        # Clean execution state (independent tracking)
        @reverse_dependencies = {}
        @clean_task_states = {}
        @clean_completed_tasks = Set.new
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

          deps.each do |dep|
            log_dependency_resolved(task_class, dep)
            queue << dep
          end
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
      ##
      # Indicates whether any tasks are currently enqueued for execution.
      # @return [Boolean] `true` if any task is enqueued, `false` otherwise.
      def running_tasks?
        @task_states.values.any? { |state| state == STATE_ENQUEUED }
      end

      # Get the total number of tasks in the dependency graph.
      #
      # @return [Integer] The number of tasks
      def task_count
        @task_states.size
      end

      # ========================================
      # Clean Operations (Reverse Dependency Order)
      # ========================================

      # Build reverse dependency graph for clean operations.
      # Clean operations run in reverse order: if A depends on B, then B must
      # be cleaned after A (so A→[B] in reverse graph means B depends on A's clean).
      #
      # Also initializes clean states for all tasks to CLEAN_STATE_PENDING.
      #
      ##
      # Builds the reverse dependency graph and initializes per-task clean execution state starting from the given root task.
      #
      # Ensures the forward dependency graph is present, clears prior clean-state data, initializes each discovered task with
      # an empty reverse-dependency set and `CLEAN_STATE_PENDING`, and populates reverse mappings so a task's clean run
      # depends on the clean completion of tasks that depend on it.
      # @param [Class] root_task_class The root task class from which to discover tasks and their dependencies.
      def build_reverse_dependency_graph(root_task_class)
        # First, ensure we have the forward dependency graph
        build_dependency_graph(root_task_class) if @dependencies.empty?

        # Clear previous clean state
        @reverse_dependencies.clear
        @clean_task_states.clear
        @clean_completed_tasks.clear

        # Initialize all tasks with empty reverse dependency sets
        @dependencies.each_key do |task_class|
          @reverse_dependencies[task_class] = Set.new
          @clean_task_states[task_class] = CLEAN_STATE_PENDING
        end

        # Build reverse mappings: if A depends on B, then B→[A] in reverse graph
        # This means B's clean depends on A's clean completing first
        @dependencies.each do |task_class, deps|
          deps.each do |dep_class|
            @reverse_dependencies[dep_class].add(task_class)
          end
        end
      end

      # Get all tasks that are ready to clean.
      # A task is ready to clean when all its reverse dependencies (dependents)
      # have completed their clean operation.
      #
      ##
      # Lists task classes that are ready for clean execution.
      # A task is considered ready when its clean state is `CLEAN_STATE_PENDING` and all of its reverse dependencies have completed their clean execution.
      # @return [Array<Class>] Array of task classes ready for clean execution.
      def next_ready_clean_tasks
        ready = []
        @clean_task_states.each_key do |task_class|
          next unless @clean_task_states[task_class] == CLEAN_STATE_PENDING
          next unless ready_to_clean?(task_class)
          ready << task_class
        end
        ready
      end

      # Mark a task as enqueued for clean execution.
      #
      ##
      # Marks the given task class as enqueued for clean execution.
      # @param [Class] task_class The task class to mark as enqueued for clean execution.
      def mark_clean_enqueued(task_class)
        @clean_task_states[task_class] = CLEAN_STATE_ENQUEUED
      end

      # Mark a task as clean completed.
      #
      ##
      # Marks the clean execution of the given task class as completed and records it.
      # @param [Class] task_class - The task class to mark as clean completed.
      def mark_clean_completed(task_class)
        @clean_task_states[task_class] = CLEAN_STATE_COMPLETED
        @clean_completed_tasks.add(task_class)
      end

      # Check if a task's clean is completed.
      #
      # @param task_class [Class] The task class to check
      ##
      # Checks whether a task class has completed its clean execution.
      # @param [Class] task_class - The task class to check.
      # @return [Boolean] `true` if the task's clean is completed, `false` otherwise.
      def clean_completed?(task_class)
        @clean_completed_tasks.include?(task_class)
      end

      # Check if there are any running (enqueued) clean tasks.
      #
      ##
      # Indicates whether any clean tasks are currently enqueued for execution.
      # @return [Boolean] `true` if at least one clean task is enqueued, `false` otherwise.
      def running_clean_tasks?
        @clean_task_states.values.any? { |state| state == CLEAN_STATE_ENQUEUED }
      end

      private

      # Check if a task is ready to execute (all dependencies completed).
      #
      # @param task_class [Class] The task class to check
      ##
      # Determines whether a task's dependencies have all completed.
      # @param [Class] task_class - The task class to check.
      # @return [Boolean] `true` if every dependency of `task_class` is in the set of completed tasks, `false` otherwise.
      def ready_to_execute?(task_class)
        task_deps = @dependencies[task_class] || Set.new
        task_deps.subset?(@completed_tasks)
      end

      # Check if a task is ready to clean (all reverse dependencies completed).
      # Reverse dependencies are tasks that depend on this task, which must
      # be cleaned before this task can be cleaned.
      #
      # @param task_class [Class] The task class to check
      ##
      # Determines whether a task is ready for clean execution.
      # @param [Class] task_class - The task class to check.
      # @return [Boolean] `true` if all tasks that depend on `task_class` have completed their clean execution, `false` otherwise.
      def ready_to_clean?(task_class)
        reverse_deps = @reverse_dependencies[task_class] || Set.new
        reverse_deps.subset?(@clean_completed_tasks)
      end

      def log_dependency_resolved(from_task, to_task)
        Taski::Logging.debug(
          Taski::Logging::Events::DEPENDENCY_RESOLVED,
          from_task: from_task.name,
          to_task: to_task.name
        )
      end
    end
  end
end
