# frozen_string_literal: true

require "prism"

module Taski
  module StaticAnalysis
    # Analyzes a task's run method AST to find dependencies that are safe
    # to speculatively pre-start (start_dep). Uses a whitelist approach:
    # only confirmed patterns are collected; unknown patterns cause the
    # analyzer to stop (returning what was collected so far up to that point).
    #
    # Currently handles variable assignment patterns only:
    #   a = Dep.value        (LocalVariableWriteNode)
    #   @a = Dep.value       (InstanceVariableWriteNode)
    #
    # This is a performance optimization only — if analysis fails or returns
    # empty, tasks still work correctly via lazy Fiber pull (need_dep).
    class StartDepAnalyzer
      DepInfo = Data.define(:klass, :method_name)

      # AST node types that are known safe (not dependencies, won't stop scanning)
      SAFE_TYPES = Set[
        Prism::LocalVariableReadNode, Prism::InstanceVariableReadNode,
        Prism::ConstantReadNode, Prism::ConstantPathNode,
        Prism::IntegerNode, Prism::FloatNode, Prism::StringNode,
        Prism::SymbolNode, Prism::NilNode, Prism::TrueNode, Prism::FalseNode,
        Prism::SelfNode
      ].freeze

      @cache = {}
      @cache_mutex = Mutex.new

      class << self
        # Analyze a task class and return deps safe to prestart.
        # Results are cached per task class.
        # @param task_class [Class] The task class to analyze
        # @return [Array<DepInfo>] Deduplicated list of safe dependencies
        def analyze(task_class)
          @cache_mutex.synchronize do
            return @cache[task_class] if @cache.key?(task_class)
          end

          result = new.analyze(task_class)

          @cache_mutex.synchronize do
            @cache[task_class] ||= result
          end
        end

        # Clear cache (for testing)
        def clear_cache!
          @cache_mutex.synchronize { @cache.clear }
        end
      end

      def initialize
        @deps = []
        @seen_classes = Set.new
      end

      # Analyze a task class's run method and return safe-to-prestart deps.
      # @param task_class [Class] The task class to analyze
      # @return [Array<DepInfo>]
      def analyze(task_class)
        @task_class = task_class
        source_location = task_class.instance_method(:run).source_location
        return [] unless source_location

        file_path, _line = source_location
        parse_result = Prism.parse_file(file_path)

        run_node = find_run_method(parse_result.value, task_class)
        return [] unless run_node&.body

        scan_statements(run_node.body)
        @deps
      rescue NameError
        []
      end

      private

      # Find the def run node inside the target class
      def find_run_method(program_node, task_class)
        target_name = task_class.name
        find_run_in_tree(program_node, [], target_name)
      end

      def find_run_in_tree(node, namespace_path, target_name)
        case node
        when Prism::ProgramNode
          node.statements.body.each do |child|
            result = find_run_in_tree(child, namespace_path, target_name)
            return result if result
          end
        when Prism::ModuleNode
          name = node.constant_path.slice
          new_path = namespace_path + [name]
          node.body&.body&.each do |child|
            result = find_run_in_tree(child, new_path, target_name)
            return result if result
          end
        when Prism::ClassNode
          name = node.constant_path.slice
          new_path = namespace_path + [name]
          full_name = new_path.join("::")

          node.body&.body&.each do |child|
            if full_name == target_name
              return child if child.is_a?(Prism::DefNode) && child.name == :run
            else
              result = find_run_in_tree(child, new_path, target_name)
              return result if result
            end
          end
        when Prism::StatementsNode
          node.body.each do |child|
            result = find_run_in_tree(child, namespace_path, target_name)
            return result if result
          end
        end

        nil
      end

      # Scan statements, collecting deps. Stops at the first unknown pattern.
      def scan_statements(node)
        return unless node.is_a?(Prism::StatementsNode)
        node.body.each { |stmt| break unless try_match(stmt) }
      end

      # Match a statement against known patterns.
      # Returns true to continue scanning, false to stop.
      def try_match(stmt)
        case stmt
        when Prism::LocalVariableWriteNode, Prism::InstanceVariableWriteNode
          check_dep_call(stmt.value)
          true
        when *SAFE_TYPES
          true
        else
          false
        end
      end

      # Check if a node is a Task dependency call (Constant.method) and collect it.
      def check_dep_call(node)
        return unless node.is_a?(Prism::CallNode)
        return unless node.receiver

        case node.receiver
        when Prism::ConstantReadNode, Prism::ConstantPathNode
          constant_name = node.receiver.slice
          resolved = resolve_constant(constant_name)
          if resolved.is_a?(Class) && defined?(Taski::Task) && resolved < Taski::Task
            collect_dep(node)
          end
        end
      end

      # Collect a dependency, deduplicating by class
      def collect_dep(call_node)
        constant_name = call_node.receiver.slice
        method_name = call_node.name
        klass = resolve_constant(constant_name)
        return unless klass

        @deps << DepInfo.new(klass: klass, method_name: method_name) if @seen_classes.add?(klass)
      end

      # Resolve a constant name to the class, with namespace fallback.
      def resolve_constant(constant_name)
        Object.const_get(constant_name)
      rescue NameError
        resolve_with_namespace(constant_name)
      end

      def resolve_with_namespace(constant_name)
        return nil unless @task_class

        namespace_parts = @task_class.name.split("::")
        namespace_parts.length.downto(0) do |i|
          prefix = namespace_parts.take(i).join("::")
          full_name = prefix.empty? ? constant_name : "#{prefix}::#{constant_name}"

          begin
            return Object.const_get(full_name)
          rescue NameError
            next
          end
        end

        nil
      end
    end
  end
end
