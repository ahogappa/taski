# frozen_string_literal: true

require "monitor"

module Taski
  module Execution
    # SharedState provides centralized, thread-safe state management for the
    # Fiber-based executor. It tracks task states, wrappers, waiters, and
    # coordinates dependency resolution between worker threads.
    #
    # All access is synchronized via a single Mutex to ensure correctness
    # when multiple worker threads access state concurrently.
    class SharedState
      STATE_PENDING = :pending
      STATE_RUNNING = :running
      STATE_COMPLETED = :completed
      STATE_ERROR = :error

      def initialize
        @mutex = Mutex.new
        @states = {}
        @wrappers = {}
        @errors = {}
        @waiters = {}
      end

      # Register a task wrapper.
      # @param task_class [Class] The task class
      # @param wrapper [TaskWrapper] The wrapper instance
      def register(task_class, wrapper)
        @mutex.synchronize do
          @wrappers[task_class] = wrapper
          @states[task_class] ||= STATE_PENDING
        end
      end

      # Attempt to transition a task from pending to running.
      # @param task_class [Class] The task class
      # @return [Boolean] true if successfully transitioned
      def mark_running(task_class)
        @mutex.synchronize do
          return false unless @states[task_class] == STATE_PENDING
          @states[task_class] = STATE_RUNNING
          true
        end
      end

      # Mark a task as completed and notify all waiters.
      # @param task_class [Class] The task class
      def mark_completed(task_class)
        waiters_to_notify = nil
        @mutex.synchronize do
          @states[task_class] = STATE_COMPLETED
          waiters_to_notify = @waiters.delete(task_class) || []
        end

        notify_waiters(task_class, waiters_to_notify)
      end

      # Mark a task as failed and notify all waiters with the error.
      # @param task_class [Class] The task class
      # @param error [Exception] The error that occurred
      def mark_failed(task_class, error)
        waiters_to_notify = nil
        @mutex.synchronize do
          @states[task_class] = STATE_ERROR
          @errors[task_class] = error
          waiters_to_notify = @waiters.delete(task_class) || []
        end

        waiters_to_notify.each do |thread_queue, fiber, _method|
          thread_queue.push([:resume_error, fiber, error])
        end
      end

      # Check if a task is completed.
      # @param task_class [Class] The task class
      # @return [Boolean]
      def completed?(task_class)
        @mutex.synchronize { @states[task_class] == STATE_COMPLETED }
      end

      # Get the wrapper for a task class.
      # @param task_class [Class] The task class
      # @return [TaskWrapper, nil]
      def get_wrapper(task_class)
        @mutex.synchronize { @wrappers[task_class] }
      end

      # Request a dependency value. Returns the resolution status:
      # - [:completed, value] if the dependency is already done
      # - [:wait] if the dependency is running (fiber will be resumed later)
      # - [:start] if the dependency hasn't been started yet (waiter registered)
      #
      # @param dep_class [Class] The dependency task class
      # @param method [Symbol] The exported method to retrieve
      # @param thread_queue [Queue] The worker thread's command queue
      # @param fiber [Fiber] The fiber to resume when dependency completes
      # @return [Array] Status tuple
      def request_dependency(dep_class, method, thread_queue, fiber)
        @mutex.synchronize do
          case @states[dep_class]
          when STATE_COMPLETED
            wrapper = @wrappers[dep_class]
            value = wrapper.task.public_send(method)
            [:completed, value]
          when STATE_ERROR
            error = @errors[dep_class]
            [:error, error]
          when STATE_RUNNING
            @waiters[dep_class] ||= []
            @waiters[dep_class] << [thread_queue, fiber, method]
            [:wait]
          else
            # Not started (pending or unknown) - register waiter and signal to start
            @waiters[dep_class] ||= []
            @waiters[dep_class] << [thread_queue, fiber, method]
            [:start]
          end
        end
      end

      private

      def notify_waiters(task_class, waiters)
        wrapper = @mutex.synchronize { @wrappers[task_class] }
        waiters.each do |thread_queue, fiber, method|
          value = wrapper.task.public_send(method)
          thread_queue.push([:resume, fiber, value])
        end
      end
    end
  end
end
