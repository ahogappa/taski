# frozen_string_literal: true

require "prism"

module Taski
  module StaticAnalysis
    class Visitor < Prism::Visitor
      attr_reader :dependencies

      def initialize(target_task_class, target_method = :run)
        super()
        @target_task_class = target_task_class
        @target_method = target_method
        @dependencies = Set.new
        @in_target_method = false
        @current_namespace_path = []
      end

      def visit_class_node(node)
        within_namespace(extract_constant_name(node.constant_path)) { super }
      end

      def visit_module_node(node)
        within_namespace(extract_constant_name(node.constant_path)) { super }
      end

      def visit_def_node(node)
        if node.name == @target_method && in_target_class?
          @in_target_method = true
          super
          @in_target_method = false
        else
          super
        end
      end

      def visit_call_node(node)
        detect_task_dependency(node) if @in_target_method
        super
      end

      def visit_constant_read_node(node)
        detect_return_constant(node) if @in_target_method && @target_method == :impl
        super
      end

      def visit_constant_path_node(node)
        detect_return_constant(node) if @in_target_method && @target_method == :impl
        super
      end

      private

      def within_namespace(name)
        @current_namespace_path.push(name)
        yield
      ensure
        @current_namespace_path.pop
      end

      def in_target_class?
        @current_namespace_path.join("::") == @target_task_class.name
      end

      def extract_constant_name(node)
        node.slice
      end

      def detect_task_dependency(node)
        return unless node.receiver

        constant_name = extract_receiver_constant(node.receiver)
        resolve_and_add_dependency(constant_name) if constant_name
      end

      def detect_return_constant(node)
        constant_name = node.slice
        resolve_and_add_dependency(constant_name)
      end

      def extract_receiver_constant(receiver)
        case receiver
        when Prism::ConstantReadNode, Prism::ConstantPathNode
          receiver.slice
        end
      end

      def resolve_and_add_dependency(constant_name)
        task_class = resolve_constant(constant_name)
        @dependencies.add(task_class) if task_class && valid_dependency?(task_class)
      end

      def resolve_constant(constant_name)
        Object.const_get(constant_name)
      rescue NameError
        resolve_with_namespace_prefix(constant_name)
      end

      def resolve_with_namespace_prefix(constant_name)
        return nil if @current_namespace_path.empty?

        @current_namespace_path.length.downto(0) do |i|
          prefix = @current_namespace_path.take(i).join("::")
          full_name = prefix.empty? ? constant_name : "#{prefix}::#{constant_name}"

          begin
            return Object.const_get(full_name)
          rescue NameError
            next
          end
        end

        nil
      end

      def valid_dependency?(klass)
        klass.is_a?(Class) &&
          (is_parallel_task?(klass) || is_parallel_section?(klass))
      end

      def is_parallel_task?(klass)
        defined?(Taski::Task) && klass < Taski::Task
      end

      def is_parallel_section?(klass)
        defined?(Taski::Section) && klass < Taski::Section
      end
    end
  end
end
