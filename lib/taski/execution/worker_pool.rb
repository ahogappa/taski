# frozen_string_literal: true

require "etc"

module Taski
  module Execution
    # WorkerPool manages a pool of worker threads that execute tasks.
    # It provides methods to start, stop, and enqueue tasks for execution.
    #
    # == Responsibilities
    #
    # - Manage worker thread lifecycle (start, shutdown)
    # - Distribute tasks to worker threads via Queue
    # - Execute tasks via callback provided by Executor
    #
    # == API
    #
    # - {#start} - Start all worker threads
    # - {#enqueue} - Add a task to the execution queue
    # - {#shutdown} - Gracefully shutdown all worker threads
    # - {#execution_queue} - Access the underlying Queue (for testing)
    #
    # == Thread Safety
    #
    # WorkerPool uses Queue for thread-safe task distribution.
    # The Queue handles synchronization between the main thread
    # (which enqueues tasks) and worker threads (which pop tasks).
    class WorkerPool
      attr_reader :execution_queue, :worker_count

      # @param registry [Registry] The task registry for thread tracking
      # @param worker_count [Integer, nil] Number of worker threads (defaults to CPU count)
      # @param on_execute [Proc] Callback to execute a task, receives (task_class, wrapper)
      def initialize(registry:, worker_count: nil, &on_execute)
        @worker_count = worker_count || default_worker_count
        @registry = registry
        @on_execute = on_execute
        @execution_queue = Queue.new
        @workers = []
      end

      # Start all worker threads.
      def start
        @worker_count.times do
          worker = Thread.new { worker_loop }
          @workers << worker
          @registry.register_thread(worker)
        end
      end

      # Enqueue a task for execution.
      #
      # @param task_class [Class] The task class to execute
      # @param wrapper [TaskWrapper] The task wrapper
      def enqueue(task_class, wrapper)
        @execution_queue.push({task_class: task_class, wrapper: wrapper})
        debug_log("Enqueued: #{task_class}")
      end

      # Shutdown all worker threads gracefully.
      def shutdown
        enqueue_shutdown_signals
        @workers.each(&:join)
      end

      # Enqueue shutdown signals for all workers.
      def enqueue_shutdown_signals
        @worker_count.times { @execution_queue.push(:shutdown) }
      end

      private

      def default_worker_count
        Etc.nprocessors.clamp(2, 8)
      end

      def worker_loop
        loop do
          work_item = @execution_queue.pop
          break if work_item == :shutdown

          task_class = work_item[:task_class]
          wrapper = work_item[:wrapper]

          debug_log("Worker executing: #{task_class}")

          begin
            @on_execute.call(task_class, wrapper)
          rescue => e
            # Log error but don't crash the worker thread.
            # Task-level errors are handled in the execute callback.
            # This catches unexpected errors in the callback itself.
            warn "[WorkerPool] Unexpected error executing #{task_class}: #{e.message}"
          end
        end
      end

      def debug_log(message)
        return unless ENV["TASKI_DEBUG"]
        puts "[WorkerPool] #{message}"
      end
    end
  end
end
