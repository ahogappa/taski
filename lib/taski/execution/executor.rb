# frozen_string_literal: true

require "monitor"
require "etc"

module Taski
  module Execution
    # Producer-Consumer pattern executor for parallel task execution.
    #
    # Architecture:
    # - Main Thread: Manages all state, coordinates execution, handles events
    # - Worker Threads: Execute tasks and send completion events
    #
    # Communication Queues:
    # - Execution Queue (Main -> Worker): Tasks ready to execute
    # - Completion Queue (Worker -> Main): Events from workers
    class Executor
      # Task execution states for the executor's internal tracking
      STATE_PENDING = :pending
      STATE_ENQUEUED = :enqueued
      STATE_COMPLETED = :completed

      class << self
        # Execute a task and all its dependencies
        # @param root_task_class [Class] The root task class to execute
        # @param registry [Registry] The task registry
        def execute(root_task_class, registry:)
          new(registry: registry).execute(root_task_class)
        end
      end

      def initialize(registry:, worker_count: nil)
        @registry = registry
        @worker_count = worker_count || default_worker_count
        @execution_queue = Queue.new
        @completion_queue = Queue.new
        @workers = []

        # State managed by main thread only
        @dependencies = {}
        @task_states = {}
        @completed_tasks = Set.new
      end

      # Execute root task and all dependencies
      # @param root_task_class [Class] The root task class to execute
      def execute(root_task_class)
        # Build dependency graph from static analysis
        build_dependency_graph(root_task_class)

        # Start worker threads
        start_workers

        # Enqueue tasks with no dependencies
        enqueue_ready_tasks

        # Main event loop - continues until root task completes
        run_main_loop(root_task_class)

        # Shutdown workers
        shutdown_workers
      end

      private

      def default_worker_count
        Etc.nprocessors.clamp(2, 8)
      end

      # Build dependency graph by traversing from root task
      # Populates @dependencies and @task_states
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

      # Enqueue tasks that have all dependencies completed
      def enqueue_ready_tasks
        @task_states.each_key do |task_class|
          next unless @task_states[task_class] == STATE_PENDING
          next unless ready_to_execute?(task_class)

          enqueue_task(task_class)
        end
      end

      # Check if a task is ready to execute
      def ready_to_execute?(task_class)
        task_deps = @dependencies[task_class] || Set.new
        task_deps.subset?(@completed_tasks)
      end

      # Enqueue a single task for execution
      def enqueue_task(task_class)
        return if @registry.abort_requested?

        @task_states[task_class] = STATE_ENQUEUED

        wrapper = get_or_create_wrapper(task_class)
        return unless wrapper.mark_running

        Taski.progress_display&.register_task(task_class)
        Taski.progress_display&.update_task(task_class, state: :running)

        @execution_queue.push({task_class: task_class, wrapper: wrapper})

        debug_log("Enqueued: #{task_class}")
      end

      # Get or create a task wrapper via Registry
      def get_or_create_wrapper(task_class)
        @registry.get_or_create(task_class) do
          task_instance = task_class.allocate
          task_instance.send(:initialize)
          TaskWrapper.new(task_instance, registry: @registry)
        end
      end

      # Start worker threads
      def start_workers
        @worker_count.times do
          worker = Thread.new { worker_loop }
          @workers << worker
          @registry.register_thread(worker)
        end
      end

      # Worker thread main loop
      def worker_loop
        loop do
          work_item = @execution_queue.pop
          break if work_item == :shutdown

          task_class = work_item[:task_class]
          wrapper = work_item[:wrapper]

          debug_log("Worker executing: #{task_class}")

          execute_task(task_class, wrapper)
        end
      end

      # Execute a task and send completion event
      def execute_task(task_class, wrapper)
        return if @registry.abort_requested?

        begin
          result = wrapper.task.run
          wrapper.mark_completed(result)
          @completion_queue.push({task_class: task_class, wrapper: wrapper})
        rescue Taski::TaskAbortException => e
          @registry.request_abort!
          wrapper.mark_failed(e)
          @completion_queue.push({task_class: task_class, wrapper: wrapper, error: e})
        rescue => e
          wrapper.mark_failed(e)
          @completion_queue.push({task_class: task_class, wrapper: wrapper, error: e})
        end
      end

      # Main thread event loop - continues until root task completes
      def run_main_loop(root_task_class)
        until @completed_tasks.include?(root_task_class)
          break if @registry.abort_requested? && no_running_tasks?

          event = @completion_queue.pop
          handle_completion(event)
        end
      end

      def no_running_tasks?
        @task_states.values.none? { |state| state == STATE_ENQUEUED }
      end

      # Handle task completion event
      def handle_completion(event)
        task_class = event[:task_class]

        debug_log("Completed: #{task_class}")

        @task_states[task_class] = STATE_COMPLETED
        @completed_tasks.add(task_class)

        # Enqueue newly ready tasks
        enqueue_ready_tasks
      end

      # Shutdown worker threads
      def shutdown_workers
        @worker_count.times { @execution_queue.push(:shutdown) }
        @workers.each(&:join)
      end

      def debug_log(message)
        return unless ENV["TASKI_DEBUG"]
        puts "[Executor] #{message}"
      end
    end
  end
end
