# frozen_string_literal: true

require_relative "static_analysis/analyzer"
require_relative "execution/registry"
require_relative "execution/coordinator"
require_relative "execution/task_wrapper"

module Taski
  class Task
    class << self
      def exports(*export_methods)
        @exported_methods = export_methods

        export_methods.each do |method|
          define_instance_reader(method)
          define_class_accessor(method)
        end
      end

      def exported_methods
        @exported_methods ||= []
      end

      # Each call creates a fresh TaskWrapper instance for re-execution support.
      # Use class methods (e.g., MyTask.result) for cached single execution.
      def new
        Execution::TaskWrapper.new(
          super,
          registry: registry,
          coordinator: coordinator
        )
      end

      def cached_dependencies
        @dependencies_cache ||= StaticAnalysis::Analyzer.analyze(self)
      end

      def clear_dependency_cache
        @dependencies_cache = nil
      end

      def run
        Taski::Context.set_root_task(self)
        cached_wrapper.run
      end

      def clean
        Taski::Context.set_root_task(self)
        cached_wrapper.clean
      end

      def registry
        Taski.global_registry
      end

      def coordinator
        @coordinator ||= Execution::Coordinator.new(
          registry: registry,
          analyzer: StaticAnalysis::Analyzer
        )
      end

      def reset!
        registry.reset!
        Taski.reset_global_registry!
        Taski::Context.reset!
        @coordinator = nil
      end

      def tree
        build_tree(self, "", Set.new)
      end

      private

      def build_tree(task_class, prefix, visited)
        result = "#{task_class.name}\n"
        return result if visited.include?(task_class)

        visited.add(task_class)
        dependencies = task_class.cached_dependencies.to_a

        dependencies.each_with_index do |dep, index|
          is_last = (index == dependencies.size - 1)
          result += format_dependency_branch(dep, prefix, is_last, visited)
        end

        result
      end

      def format_dependency_branch(dep, prefix, is_last, visited)
        connector, extension = tree_connector_chars(is_last)
        dep_tree = build_tree(dep, "#{prefix}#{extension}", visited)

        result = "#{prefix}#{connector}"
        lines = dep_tree.lines
        result += lines.first
        lines[1..].each { |line| result += line }
        result
      end

      def tree_connector_chars(is_last)
        if is_last
          ["└── ", "    "]
        else
          ["├── ", "│   "]
        end
      end

      # Use allocate + initialize instead of new to avoid infinite loop
      # since new is overridden to return TaskWrapper
      def cached_wrapper
        registry.get_or_create(self) do
          task_instance = allocate
          task_instance.send(:initialize)
          Execution::TaskWrapper.new(
            task_instance,
            registry: registry,
            coordinator: coordinator
          )
        end
      end

      def define_instance_reader(method)
        undef_method(method) if method_defined?(method)

        define_method(method) do
          instance_variable_get("@#{method}")
        end
      end

      def define_class_accessor(method)
        singleton_class.undef_method(method) if singleton_class.method_defined?(method)

        define_singleton_method(method) do
          Taski::Context.set_root_task(self)
          cached_wrapper.get_exported_value(method)
        end
      end
    end

    def run
      raise NotImplementedError, "Subclasses must implement the run method"
    end

    def clean
    end

    def reset!
      self.class.exported_methods.each do |method|
        instance_variable_set("@#{method}", nil)
      end
    end
  end
end
