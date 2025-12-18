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
          registry: fresh_registry
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
        build_tree(self, "", {}, false)
      end

      private

      # ANSI color codes
      COLORS = {
        reset: "\e[0m",
        task: "\e[32m",      # green
        section: "\e[34m",   # blue
        impl: "\e[33m",      # yellow
        tree: "\e[90m",      # gray
        name: "\e[1m"        # bold
      }.freeze

      def build_tree(task_class, prefix, task_index_map, is_impl, ancestors = Set.new)
        type_label = colored_type_label(task_class)
        impl_prefix = is_impl ? "#{COLORS[:impl]}[impl]#{COLORS[:reset]} " : ""
        task_number = get_task_number(task_class, task_index_map)
        name = "#{COLORS[:name]}#{task_class.name}#{COLORS[:reset]}"

        # Detect circular reference
        if ancestors.include?(task_class)
          circular_marker = "#{COLORS[:impl]}(circular)#{COLORS[:reset]}"
          return "#{impl_prefix}#{task_number} #{name} #{type_label} #{circular_marker}\n"
        end

        result = "#{impl_prefix}#{task_number} #{name} #{type_label}\n"

        # Register task number if not already registered
        task_index_map[task_class] = task_index_map.size + 1 unless task_index_map.key?(task_class)

        # Add to ancestors for circular detection
        new_ancestors = ancestors + [task_class]

        # Use static analysis to include Section.impl candidates for visualization
        dependencies = StaticAnalysis::Analyzer.analyze(task_class).to_a
        is_section = section_class?(task_class)

        dependencies.each_with_index do |dep, index|
          is_last = (index == dependencies.size - 1)
          result += format_dependency_branch(dep, prefix, is_last, task_index_map, is_section, new_ancestors)
        end

        result
      end

      def format_dependency_branch(dep, prefix, is_last, task_index_map, is_impl, ancestors)
        connector, extension = tree_connector_chars(is_last)
        dep_tree = build_tree(dep, "#{prefix}#{extension}", task_index_map, is_impl, ancestors)

        result = "#{prefix}#{COLORS[:tree]}#{connector}#{COLORS[:reset]}"
        lines = dep_tree.lines
        result += lines.first
        lines.drop(1).each { |line| result += line }
        result
      end

      def tree_connector_chars(is_last)
        if is_last
          ["└── ", "    "]
        else
          ["├── ", "│   "]
        end
      end

      def get_task_number(task_class, task_index_map)
        number = task_index_map[task_class] || (task_index_map.size + 1)
        "#{COLORS[:tree]}[#{number}]#{COLORS[:reset]}"
      end

      def colored_type_label(klass)
        if section_class?(klass)
          "#{COLORS[:section]}(Section)#{COLORS[:reset]}"
        else
          "#{COLORS[:task]}(Task)#{COLORS[:reset]}"
        end
      end

      def section_class?(klass)
        defined?(Taski::Section) && klass < Taski::Section
      end

      # Use allocate + initialize instead of new to avoid infinite loop
      # since new is overridden to return TaskWrapper
      def cached_wrapper
        registry.get_or_create(self) do
          task_instance = allocate
          task_instance.send(:initialize)
          Execution::TaskWrapper.new(
            task_instance,
            registry: registry
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

    def reset!
      self.class.exported_methods.each do |method|
        instance_variable_set("@#{method}", nil)
      end
    end
  end
end
