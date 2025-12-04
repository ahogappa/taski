# frozen_string_literal: true

module Taski
  module Execution
    # Coordinates parallel execution of task dependencies
    class Coordinator
      def initialize(registry:, analyzer:)
        @registry = registry
        @analyzer = analyzer
      end

      # Start all dependencies for a given task class in parallel
      #
      # @param task_class [Class] The task class whose dependencies should be started
      def start_dependencies(task_class)
        dependencies = get_dependencies(task_class)
        return if dependencies.empty?

        dependencies.each do |dep_class|
          start_dependency_execution(dep_class)
        end
      end

      # Start clean for all dependencies in parallel (for reverse execution)
      #
      # @param task_class [Class] The task class whose dependencies should be cleaned
      def start_clean_dependencies(task_class)
        dependencies = get_dependencies(task_class)
        return if dependencies.empty?

        dependencies.each do |dep_class|
          start_dependency_clean(dep_class)
        end
      end

      private

      def get_dependencies(task_class)
        # Use cached dependencies if available
        # NOTE: Using respond_to? here to check for optional caching feature.
        # This allows tasks to optionally provide cached dependencies for performance.
        if task_class.respond_to?(:cached_dependencies)
          task_class.cached_dependencies
        else
          @analyzer.analyze(task_class)
        end
      end

      # Start a new thread and register it with the registry
      #
      # @yield Block to execute in the thread
      def start_thread_with(&block)
        thread = Thread.new(&block)
        @registry.register_thread(thread)
      end

      def start_dependency_execution(dep_class)
        exported_methods = dep_class.exported_methods

        exported_methods.each do |method|
          start_thread_with do
            # NOTE: Using public_send here is unavoidable as we need to dynamically
            # call exported methods. This triggers the task execution in parallel.
            dep_class.public_send(method)
          end
        end
      end

      def start_dependency_clean(dep_class)
        start_thread_with do
          # NOTE: Using public_send here is unavoidable for dynamic clean method call
          dep_class.public_send(:clean)
        end
      end
    end
  end
end
