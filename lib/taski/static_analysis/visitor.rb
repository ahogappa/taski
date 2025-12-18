# frozen_string_literal: true

require "prism"

module Taski
  module StaticAnalysis
    class Visitor < Prism::Visitor
      attr_reader :dependencies

      # @param target_task_class [Class] The task class to analyze
      # @param target_method [Symbol] The method name to analyze (:run or :impl)
      # @param methods_to_analyze [Set<Symbol>] Set of method names to analyze (for following calls)
      def initialize(target_task_class, target_method = :run, methods_to_analyze = nil)
        super()
        @target_task_class = target_task_class
        @target_method = target_method
        @dependencies = Set.new
        @in_target_method = false
        @current_namespace_path = []
        # Methods to analyze: starts with just the target method, grows as we find calls
        @methods_to_analyze = methods_to_analyze || Set.new([@target_method])
        # Track which methods we've already analyzed to prevent infinite loops
        @analyzed_methods = Set.new
        # Collect method calls made within analyzed methods (for following)
        @method_calls_to_follow = Set.new
        # Store method definitions found in the class for later analysis
        @class_method_defs = {}
        # Track if we're in an impl call chain (for Section constant detection)
        @in_impl_chain = false
      end

      def visit_class_node(node)
        within_namespace(extract_constant_name(node.constant_path)) do
          if in_target_class?
            # First pass: collect all method definitions in the target class
            collect_method_definitions(node)
          end
          super
        end
      end

      def visit_module_node(node)
        within_namespace(extract_constant_name(node.constant_path)) { super }
      end

      def visit_def_node(node)
        if in_target_class? && should_analyze_method?(node.name)
          @analyzed_methods.add(node.name)
          @in_target_method = true
          @current_analyzing_method = node.name
          # Start impl chain when entering impl method
          @in_impl_chain = true if node.name == :impl && @target_method == :impl
          super
          @in_target_method = false
          @current_analyzing_method = nil
        else
          super
        end
      end

      def visit_call_node(node)
        if @in_target_method
          detect_task_dependency(node)
          detect_method_call_to_follow(node)
        end
        super
      end

      def visit_constant_read_node(node)
        # For Section.impl, detect constants as impl candidates (static dependencies)
        detect_impl_candidate(node) if in_impl_method?
        super
      end

      def visit_constant_path_node(node)
        # For Section.impl, detect constants as impl candidates (static dependencies)
        detect_impl_candidate(node) if in_impl_method?
        super
      end

      # After visiting, follow any method calls that need analysis
      def follow_method_calls
        new_methods = @method_calls_to_follow - @analyzed_methods
        return if new_methods.empty?

        # Add new methods to analyze
        @methods_to_analyze.merge(new_methods)
        @method_calls_to_follow.clear

        # Re-analyze the class methods
        @class_method_defs.each do |method_name, method_node|
          next unless new_methods.include?(method_name)

          @analyzed_methods.add(method_name)
          @in_target_method = true
          @current_analyzing_method = method_name
          visit(method_node)
          @in_target_method = false
          @current_analyzing_method = nil
        end

        # Recursively follow any new calls discovered
        follow_method_calls
      end

      private

      # Collect all method definitions in the target class for later analysis
      def collect_method_definitions(class_node)
        class_node.body&.body&.each do |node|
          if node.is_a?(Prism::DefNode)
            @class_method_defs[node.name] = node
          end
        end
      end

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

      def should_analyze_method?(method_name)
        @methods_to_analyze.include?(method_name) && !@analyzed_methods.include?(method_name)
      end

      def in_impl_method?
        @in_target_method && @in_impl_chain
      end

      # Detect method calls that should be followed (calls to methods in the same class)
      def detect_method_call_to_follow(node)
        # Only follow calls without explicit receiver (self.method or just method)
        return if node.receiver && !self_receiver?(node.receiver)

        method_name = node.name
        # Mark this method for later analysis if it's defined in the class
        @method_calls_to_follow.add(method_name) if @class_method_defs.key?(method_name)
      end

      def self_receiver?(receiver)
        receiver.is_a?(Prism::SelfNode)
      end

      def detect_impl_candidate(node)
        constant_name = node.slice
        resolve_and_add_dependency(constant_name)
      end

      def detect_task_dependency(node)
        return unless node.receiver

        constant_name = extract_receiver_constant(node.receiver)
        resolve_and_add_dependency(constant_name) if constant_name
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
