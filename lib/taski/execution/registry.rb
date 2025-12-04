# frozen_string_literal: true

require "monitor"

module Taski
  module Execution
    # Central registry for task instances and execution threads
    class Registry
      def initialize
        @tasks = {}
        @threads = []
        @monitor = Monitor.new
        @abort_requested = false
      end

      # Get or create a task instance
      #
      # @param task_class [Class] The task class
      # @yield Block to create the task instance if it doesn't exist
      # @return [Object] The task instance
      def get_or_create(task_class)
        @tasks[task_class] ||= yield
      end

      # Get an existing task instance
      #
      # @param task_class [Class] The task class
      # @return [Object] The task instance
      # @raise [RuntimeError] If the task is not registered
      def get_task(task_class)
        @tasks.fetch(task_class) do
          raise "Task #{task_class} not registered"
        end
      end

      # Register a thread for tracking
      #
      # @param thread [Thread] The thread to register
      def register_thread(thread)
        @monitor.synchronize { @threads << thread }
      end

      # Wait for all registered threads to complete
      def wait_all
        threads = @monitor.synchronize { @threads.dup }
        threads.each(&:join)
      end

      # Reset the registry (clear all tasks and threads)
      def reset!
        @monitor.synchronize do
          @tasks.clear
          @threads.clear
          @abort_requested = false
        end
      end

      # Request abort for all pending tasks
      def request_abort!
        @monitor.synchronize { @abort_requested = true }
      end

      # Check if abort has been requested
      #
      # @return [Boolean] true if abort has been requested
      def abort_requested?
        @monitor.synchronize { @abort_requested }
      end

      # Run a task and wait for all dependencies to complete
      #
      # @param task_class [Class] The task class to run
      # @param exported_methods [Array<Symbol>] Methods to call to trigger execution
      # @return [Object] The result of the task execution
      def run(task_class, exported_methods)
        # Trigger execution of all exported methods
        # NOTE: Using public_send here is unavoidable as we need to dynamically
        # call methods based on the exported_methods array. This is a core part
        # of the export mechanism design.
        exported_methods.each do |method|
          task_class.public_send(method)
        end

        # Wait for all threads to complete
        wait_all

        # Return the result
        get_task(task_class).result
      end
    end
  end
end
