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
        @monitor.synchronize do
          @tasks[task_class] ||= yield
        end
      end

      # @param task_class [Class] The task class
      # @param wrapper [TaskWrapper] The wrapper instance to register
      def register(task_class, wrapper)
        @tasks[task_class] = wrapper
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

      # @return [Array<TaskWrapper>] All wrappers that have errors
      def failed_wrappers
        @monitor.synchronize do
          @tasks.values.select { |w| w.error }
        end
      end

      # @return [Array<TaskWrapper>] All wrappers that have clean errors
      def failed_clean_wrappers
        @monitor.synchronize do
          @tasks.values.select { |w| w.clean_error }
        end
      end

      # Create or retrieve a TaskWrapper for the given task class.
      # Encapsulates the standard wrapper creation pattern used by Executor and WorkerPool.
      # @param task_class [Class] The task class
      # @param execution_context [ExecutionContext] The execution context
      # @return [TaskWrapper] The wrapper instance
      def create_wrapper(task_class, execution_context:)
        get_or_create(task_class) do
          task_instance = task_class.allocate
          task_instance.send(:initialize)
          TaskWrapper.new(task_instance, registry: self, execution_context: execution_context)
        end
      end

      # @param task_class [Class] The task class to run
      # @param exported_methods [Array<Symbol>] Methods to call to trigger execution
      # @return [Object] The result of the task execution
      def run(task_class, exported_methods)
        exported_methods.each do |method|
          task_class.public_send(method)
        end

        wait_all

        # @type var wrapper: Taski::Execution::TaskWrapper
        wrapper = get_task(task_class)
        wrapper.result
      end
    end
  end
end
