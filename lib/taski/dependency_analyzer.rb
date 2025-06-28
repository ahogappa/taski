# frozen_string_literal: true

require "prism"

module Taski
  module DependencyAnalyzer
    class << self
      def analyze_method(klass, method_name)
        return [] unless klass.instance_methods(false).include?(method_name)

        method = klass.instance_method(method_name)
        source_location = method.source_location
        return [] unless source_location

        file_path, line_number = source_location
        return [] unless File.exist?(file_path)

        begin
          result = Prism.parse_file(file_path)

          unless result.success?
            Taski.logger.error("Parse errors in source file",
              file: file_path,
              errors: result.errors.map(&:message),
              method: "#{klass}##{method_name}")
            return []
          end

          # Handle warnings if present
          if result.warnings.any?
            Taski.logger.warn("Parse warnings in source file",
              file: file_path,
              warnings: result.warnings.map(&:message),
              method: "#{klass}##{method_name}")
          end

          dependencies = []
          method_node = find_method_node(result.value, method_name, line_number)

          if method_node
            visitor = TaskDependencyVisitor.new(klass)
            visitor.visit(method_node)
            dependencies = visitor.dependencies
          end

          dependencies.uniq
        rescue IOError, SystemCallError => e
          Taski.logger.error("Failed to read source file",
            file: file_path,
            error: e.message,
            method: "#{klass}##{method_name}")
          []
        rescue => e
          Taski.logger.error("Failed to analyze method dependencies",
            class: klass.name,
            method: method_name,
            error: e.message,
            error_class: e.class.name)
          []
        end
      end

      private

      def find_method_node(node, method_name, target_line)
        return nil unless node

        case node
        when Prism::DefNode
          if node.name == method_name && node.location.start_line <= target_line && node.location.end_line >= target_line
            return node
          end
        when Prism::ClassNode, Prism::ModuleNode
          if node.respond_to?(:body)
            return find_method_node(node.body, method_name, target_line)
          end
        when Prism::StatementsNode
          node.body.each do |child|
            result = find_method_node(child, method_name, target_line)
            return result if result
          end
        end

        # Recursively search child nodes
        if node.respond_to?(:child_nodes)
          node.child_nodes.each do |child|
            result = find_method_node(child, method_name, target_line)
            return result if result
          end
        end

        nil
      end

      # Task dependency visitor using Prism's visitor pattern
      class TaskDependencyVisitor < Prism::Visitor
        attr_reader :dependencies

        def initialize(context_class = nil)
          @dependencies = []
          @constant_cache = {}
          @context_class = context_class
        end

        def visit_constant_read_node(node)
          check_task_constant(node.name.to_s)
          super
        end

        def visit_constant_path_node(node)
          const_path = extract_constant_path(node)
          check_task_constant(const_path) if const_path
          super
        end

        def visit_call_node(node)
          # Check for method calls on constants (e.g., TaskA.result)
          case node.receiver
          when Prism::ConstantReadNode
            check_task_constant(node.receiver.name.to_s)
          when Prism::ConstantPathNode
            const_path = extract_constant_path(node.receiver)
            check_task_constant(const_path) if const_path
          end
          super
        end

        private

        def check_task_constant(const_name)
          return unless const_name

          # Use caching to avoid repeated constant resolution
          cached_result = @constant_cache[const_name]
          return cached_result if cached_result == false # Cached negative result
          return @dependencies << cached_result if cached_result # Cached positive result

          begin
            resolved_class = nil

            # 1. Try absolute reference first (existing logic)
            if Object.const_defined?(const_name)
              resolved_class = Object.const_get(const_name)
            # 2. Try relative reference within namespace context
            elsif @context_class
              resolved_class = resolve_relative_constant(const_name)
            end

            if resolved_class&.is_a?(Class) && resolved_class < Taski::Task
              @constant_cache[const_name] = resolved_class
              @dependencies << resolved_class
            else
              @constant_cache[const_name] = false
            end
          rescue NameError, ArgumentError
            @constant_cache[const_name] = false
          end
        end

        def resolve_relative_constant(const_name)
          return nil unless @context_class

          # Get the namespace from the context class
          namespace = get_namespace_from_class(@context_class)
          return nil unless namespace

          # Try to resolve the constant within the namespace
          full_const_name = "#{namespace}::#{const_name}"
          Object.const_get(full_const_name) if Object.const_defined?(full_const_name)
        rescue NameError, ArgumentError
          nil
        end

        def get_namespace_from_class(klass)
          # Extract namespace from class name (e.g., "A::AB" -> "A")
          class_name = klass.name
          return nil unless class_name&.include?("::")

          # Split by "::" and take all but the last part
          parts = class_name.split("::")
          return nil if parts.length <= 1  # No namespace

          parts[0..-2].join("::")
        end

        def extract_constant_path(node)
          case node
          when Prism::ConstantReadNode
            node.name.to_s
          when Prism::ConstantPathNode
            parent_path = extract_constant_path(node.parent) if node.parent
            child_name = node.name.to_s

            if parent_path && child_name
              "#{parent_path}::#{child_name}"
            else
              child_name
            end
          end
        end
      end
    end
  end
end
