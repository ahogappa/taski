# frozen_string_literal: true

require "monitor"

module Taski
  module Execution
    class Registry
      def initialize
        @tasks = {}
        @threads = []
        @monitor = Monitor.new
        @abort_requested = false
      end

      # @param task_class [Class] The task class
      # @yield Block to create the task instance if it doesn't exist
      # @return [Object] The task instance
      def get_or_create(task_class)
        @tasks[task_class] ||= yield
      end

      # @param task_class [Class] The task class
      # @return [Object] The task instance
      # @raise [RuntimeError] If the task is not registered
      def get_task(task_class)
        @tasks.fetch(task_class) do
          raise "Task #{task_class} not registered"
        end
      end

      # @param thread [Thread] The thread to register
      def register_thread(thread)
        @monitor.synchronize { @threads << thread }
      end

      def wait_all
        threads = @monitor.synchronize { @threads.dup }
        threads.each(&:join)
      end

      def reset!
        @monitor.synchronize do
          @tasks.clear
          @threads.clear
          @abort_requested = false
        end
      end

      def request_abort!
        @monitor.synchronize { @abort_requested = true }
      end

      # @return [Boolean] true if abort has been requested
      def abort_requested?
        @monitor.synchronize { @abort_requested }
      end

      # @param task_class [Class] The task class to run
      # @param exported_methods [Array<Symbol>] Methods to call to trigger execution
      # @return [Object] The result of the task execution
      def run(task_class, exported_methods)
        exported_methods.each do |method|
          task_class.public_send(method)
        end

        wait_all

        get_task(task_class).result
      end
    end
  end
end
