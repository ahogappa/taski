# frozen_string_literal: true

require_relative "static_analysis/analyzer"
require_relative "execution/registry"
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
        fresh_registry = Execution::Registry.new
        task_instance = allocate
        task_instance.send(:initialize)
        wrapper = Execution::TaskWrapper.new(
          task_instance,
          registry: fresh_registry,
          execution_context: Execution::ExecutionContext.current
        )
        # Pre-register to prevent Executor from creating a duplicate wrapper
        fresh_registry.register(self, wrapper)
        wrapper
      end

      def cached_dependencies
        @dependencies_cache ||= StaticAnalysis::Analyzer.analyze(self)
      end

      def clear_dependency_cache
        @dependencies_cache = nil
      end

      def run(context: {})
        Taski.start_context(options: context, root_task: self)
        validate_no_circular_dependencies!
        cached_wrapper.run
      end

      def clean(context: {})
        Taski.start_context(options: context, root_task: self)
        validate_no_circular_dependencies!
        cached_wrapper.clean
      end

      def registry
        Taski.global_registry
      end

      def reset!
        registry.reset!
        Taski.reset_global_registry!
        Taski.reset_context!
        @circular_dependency_checked = false
      end

      def tree
        Execution::TreeProgressDisplay.render_static_tree(self)
      end

      private

      # Use allocate + initialize instead of new to avoid infinite loop
      # since new is overridden to return TaskWrapper
      def cached_wrapper
        registry.get_or_create(self) do
          task_instance = allocate
          task_instance.send(:initialize)
          Execution::TaskWrapper.new(
            task_instance,
            registry: registry,
            execution_context: Execution::ExecutionContext.current
          )
        end
      end

      def define_instance_reader(method)
        undef_method(method) if method_defined?(method)

        define_method(method) do
          # @type self: Task
          instance_variable_get("@#{method}")
        end
      end

      def define_class_accessor(method)
        singleton_class.undef_method(method) if singleton_class.method_defined?(method)

        define_singleton_method(method) do
          Taski.start_context(options: {}, root_task: self)
          validate_no_circular_dependencies!
          cached_wrapper.get_exported_value(method)
        end
      end

      def validate_no_circular_dependencies!
        return if @circular_dependency_checked

        graph = StaticAnalysis::DependencyGraph.new.build_from(self)
        cyclic_components = graph.cyclic_components

        if cyclic_components.any?
          raise Taski::CircularDependencyError.new(cyclic_components)
        end

        @circular_dependency_checked = true
      end
    end

    def run
      raise NotImplementedError, "Subclasses must implement the run method"
    end

    def clean
    end

    # Override system() to capture subprocess output through the pipe-based architecture.
    # Uses Kernel.system with :out option to redirect output to the task's pipe.
    # If user provides :out or :err options, they are respected (no automatic redirection).
    # @param args [Array] Command arguments (shell mode if single string, exec mode if array)
    # @param opts [Hash] Options passed to Kernel.system
    # @return [Boolean, nil] true if command succeeded, false if failed, nil if command not found
    def system(*args, **opts)
      write_io = $stdout.respond_to?(:current_write_io) ? $stdout.current_write_io : nil

      if write_io && !opts.key?(:out)
        # Redirect subprocess output to the task's pipe (stderr merged into stdout)
        Kernel.system(*args, out: write_io, err: [:child, :out], **opts)
      else
        # No capture active or user provided custom :out, use normal system
        Kernel.system(*args, **opts)
      end
    end

    def reset!
      self.class.exported_methods.each do |method|
        instance_variable_set("@#{method}", nil)
      end
    end
  end
end
