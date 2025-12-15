# frozen_string_literal: true

module Taski
  module Execution
    class Coordinator
      def initialize(registry:, analyzer:)
        @registry = registry
        @analyzer = analyzer
      end

      # @param task_class [Class] The task class whose dependencies should be started
      def start_dependencies(task_class)
        dependencies = get_dependencies(task_class)
        return if dependencies.empty?

        dependencies.each do |dep_class|
          start_dependency_execution(dep_class)
        end
      end

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
        if task_class.respond_to?(:cached_dependencies)
          task_class.cached_dependencies
        else
          @analyzer.analyze(task_class)
        end
      end

      def start_thread_with(&block)
        thread = Thread.new(&block)
        @registry.register_thread(thread)
      end

      def start_dependency_execution(dep_class)
        exported_methods = dep_class.exported_methods

        exported_methods.each do |method|
          start_thread_with do
            dep_class.public_send(method)
          end
        end
      end

      def start_dependency_clean(dep_class)
        start_thread_with do
          dep_class.public_send(:clean)
        end
      end
    end
  end
end
