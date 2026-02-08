# frozen_string_literal: true

module Taski
  module Execution
    # Scheduler manages task dependency state and determines execution order.
    # Both run and clean phases use the same unified state set:
    # :pending, :running, :completed, :failed, :skipped.
    #
    # == State Transitions
    #
    # Run phase:   pending → running → completed | failed
    #              pending → skipped (when a dependency fails)
    # Clean phase: pending → running → completed
    #
    # == Responsibilities
    #
    # - Load pre-built dependency graph from Executor
    # - Track task states: pending, running, completed
    # - Determine which tasks are ready to execute (all dependencies completed)
    # - Provide next_ready_tasks for the Executor's event loop
    # - Build reverse dependency graph for clean operations
    # - Track clean states independently from run states
    # - Provide next_ready_clean_tasks for reverse dependency order execution
    #
    # == API
    #
    # Run operations:
    # - {#load_graph} - Load pre-built dependency graph
    # - {#next_ready_tasks} - Get tasks ready for execution
    # - {#mark_running} - Mark task as sent to worker pool
    # - {#mark_completed} - Mark task as finished
    # - {#completed?} - Check if task is completed
    # - {#running_tasks?} - Check if any tasks are currently executing
    #
    # Clean operations:
    # - {#build_reverse_dependency_graph} - Build reverse graph for clean order
    # - {#next_ready_clean_tasks} - Get tasks ready for clean (reverse order)
    # - {#mark_clean_running} - Mark task as sent for clean
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
      # Unified task execution states (used by both run and clean phases)
      STATE_PENDING = :pending
      STATE_RUNNING = :running
      STATE_COMPLETED = :completed
      STATE_FAILED = :failed
      STATE_SKIPPED = :skipped

      ##
      # Initializes internal data structures used to track normal and clean task execution.
      def initialize
        # Run execution state
        @dependencies = {}
        @task_states = {}
        @finished_tasks = Set.new
        @run_reverse_deps = {}

        # Clean execution state (independent tracking, same state values)
        @reverse_dependencies = {}
        @clean_task_states = {}
        @clean_finished_tasks = Set.new
      end

      # Load dependency graph from a pre-built DependencyGraph.
      # Populates internal state with all tasks and their dependencies via BFS from root.
      #
      # @param dependency_graph [StaticAnalysis::DependencyGraph] Pre-built graph
      # @param root_task_class [Class] The root task class to start from
      def load_graph(dependency_graph, root_task_class)
        # @type var queue: Array[singleton(Taski::Task)]
        queue = [root_task_class]

        while (task_class = queue.shift)
          next if @task_states.key?(task_class)

          deps = dependency_graph.dependencies_for(task_class)
          @dependencies[task_class] = deps.dup
          @task_states[task_class] = STATE_PENDING
          @run_reverse_deps[task_class] ||= Set.new

          deps.each do |dep|
            @run_reverse_deps[dep] ||= Set.new
            @run_reverse_deps[dep].add(task_class)
            log_dependency_resolved(task_class, dep)
            queue << dep
          end
        end
      end

      # Get all tasks that are ready to execute.
      # A task is ready when it is pending and all its dependencies are completed.
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

      # Mark a task as running (sent to worker pool).
      # Prevents the task from being selected again by next_ready_tasks.
      #
      # @param task_class [Class] The task class to mark
      def mark_running(task_class)
        @task_states[task_class] = STATE_RUNNING
      end

      # Mark a task as completed.
      #
      # @param task_class [Class] The task class to mark
      def mark_completed(task_class)
        @task_states[task_class] = STATE_COMPLETED
        @finished_tasks.add(task_class)
      end

      # Mark a task as failed.
      # Failed tasks are added to the finished set so dependents can proceed
      # (they will be skipped by the Executor's skip_pending_dependents).
      #
      # @param task_class [Class] The task class to mark
      def mark_failed(task_class)
        @task_states[task_class] = STATE_FAILED
        @finished_tasks.add(task_class)
      end

      # Check if a task is completed.
      #
      # @param task_class [Class] The task class to check
      # @return [Boolean] true if the task is completed
      def completed?(task_class)
        @finished_tasks.include?(task_class)
      end

      # Check if there are any running tasks.
      #
      # @return [Boolean] true if any task is running, false otherwise.
      def running_tasks?
        @task_states.values.any? { |state| state == STATE_RUNNING }
      end

      # Get the total number of tasks in the dependency graph.
      #
      # @return [Integer] The number of tasks
      def task_count
        @task_states.size
      end

      # Get task classes that were never executed (remained in STATE_PENDING).
      # These are tasks discovered by the static dependency graph
      # (via load_graph) but not reached at runtime — e.g.,
      # skipped due to conditional logic inside Task#run or because the
      # root task completed before all statically-discovered tasks were needed.
      #
      # @return [Array<Class>] Array of task classes still pending
      def skipped_task_classes
        @task_states.select { |_, state| state == STATE_PENDING }.keys
      end

      # Mark a task as skipped (never executed). Only transitions from pending.
      #
      # @param task_class [Class] The task class to mark as skipped
      # @return [Boolean] true if the state was changed
      def mark_skipped(task_class)
        return false unless @task_states[task_class] == STATE_PENDING
        @task_states[task_class] = STATE_SKIPPED
        true
      end

      # Get the count of tasks in STATE_SKIPPED.
      #
      # @return [Integer] Number of explicitly skipped tasks
      def skipped_count
        @task_states.count { |_, state| state == STATE_SKIPPED }
      end

      # Check if a task was actually executed during the run phase.
      # Returns false for tasks that remained pending or were skipped.
      #
      # @param task_class [Class] The task class to check
      # @return [Boolean] true if the task was executed (completed or running)
      def was_executed?(task_class)
        state = @task_states[task_class]
        state != STATE_PENDING && state != STATE_SKIPPED
      end

      # Find all pending tasks that transitively depend on the given task.
      # Traverses the reverse dependency graph (run phase) using BFS.
      # Only returns tasks in STATE_PENDING; running/completed tasks are
      # traversed through but not included in results.
      #
      # @param task_class [Class] The task to find dependents of
      # @return [Array<Class>] Pending transitive dependents
      def pending_dependents_of(task_class)
        result = []
        queue = [task_class]
        visited = Set.new([task_class])

        while (tc = queue.shift)
          dependents = @run_reverse_deps[tc] || Set.new
          dependents.each do |dep|
            next if visited.include?(dep)
            visited.add(dep)

            result << dep if @task_states[dep] == STATE_PENDING
            queue << dep
          end
        end

        result
      end

      # ========================================
      # Clean Operations (Reverse Dependency Order)
      # ========================================

      # Build reverse dependency graph for clean operations.
      # Clean operations run in reverse order: if A depends on B, then B must
      # be cleaned after A (so A→[B] in reverse graph means B depends on A's clean).
      #
      # Requires load_graph to have been called first to populate @dependencies.
      # Also initializes clean states for all tasks to STATE_PENDING.
      def build_reverse_dependency_graph
        # Clear previous clean state
        @reverse_dependencies.clear
        @clean_task_states.clear
        @clean_finished_tasks.clear

        # Initialize all tasks with empty reverse dependency sets
        @dependencies.each_key do |task_class|
          @reverse_dependencies[task_class] = Set.new
          @clean_task_states[task_class] = STATE_PENDING
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
      # A task is ready to clean when it is pending and all its reverse
      # dependencies (dependents) have completed their clean operation.
      #
      # @return [Array<Class>] Array of task classes ready for clean execution.
      def next_ready_clean_tasks
        ready = []
        @clean_task_states.each_key do |task_class|
          next unless @clean_task_states[task_class] == STATE_PENDING
          next unless ready_to_clean?(task_class)
          ready << task_class
        end
        ready
      end

      # Mark a task as running for clean execution.
      #
      # @param task_class [Class] The task class to mark as running for clean.
      def mark_clean_running(task_class)
        @clean_task_states[task_class] = STATE_RUNNING
      end

      # Mark a task as clean completed.
      #
      # @param task_class [Class] The task class to mark as clean completed.
      def mark_clean_completed(task_class)
        @clean_task_states[task_class] = STATE_COMPLETED
        @clean_finished_tasks.add(task_class)
      end

      # Check if a task's clean is completed.
      #
      # @param task_class [Class] The task class to check.
      # @return [Boolean] true if the task's clean is completed, false otherwise.
      def clean_completed?(task_class)
        @clean_finished_tasks.include?(task_class)
      end

      # Check if there are any running clean tasks.
      #
      # @return [Boolean] true if at least one clean task is running, false otherwise.
      def running_clean_tasks?
        @clean_task_states.values.any? { |state| state == STATE_RUNNING }
      end

      private

      # Check if a task is ready to execute (all dependencies completed).
      def ready_to_execute?(task_class)
        task_deps = @dependencies[task_class] || Set.new
        task_deps.subset?(@finished_tasks)
      end

      # Check if a task is ready to clean (all reverse dependencies completed).
      def ready_to_clean?(task_class)
        reverse_deps = @reverse_dependencies[task_class] || Set.new
        reverse_deps.subset?(@clean_finished_tasks)
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
