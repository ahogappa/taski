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
      AnalysisResult = Data.define(:start_deps, :sync_deps)

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

      EMPTY_RESULT = AnalysisResult.new(start_deps: Set.new.freeze, sync_deps: Set.new.freeze).freeze

      def initialize
        @deps = []
        @seen_classes = Set.new
      end

      # Analyze a task class's run method and return safe-to-prestart deps
      # and sync_dep_classes (deps whose proxy variables are used unsafely).
      # @param task_class [Class] The task class to analyze
      # @return [AnalysisResult]
      def analyze(task_class)
        @task_class = task_class
        source_location = task_class.instance_method(:run).source_location
        return EMPTY_RESULT unless source_location

        file_path, _line = source_location
        parse_result = Prism.parse_file(file_path)

        run_node = find_run_method(parse_result.value, task_class)
        return EMPTY_RESULT unless run_node&.body

        scan_statements(run_node.body)
        unsafe_classes = detect_unsafe_proxy_usage(run_node.body)
        all_dep_classes = Set.new(@deps.map(&:klass))
        start_deps = all_dep_classes - unsafe_classes
        sync_deps = unsafe_classes
        AnalysisResult.new(start_deps: start_deps, sync_deps: sync_deps)
      rescue NameError
        EMPTY_RESULT
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

      # Phase 2: Detect proxy variables used in unsafe contexts.
      # Returns a Set of dep classes whose proxy variables are used unsafely.
      # A proxy variable is a local variable assigned from a Taski::Task dep call
      # (e.g., `a = Dep.value`). If such a variable is later used in an unsafe
      # context (as argument, condition, array element, etc.), the dep class is
      # added to sync_dep_classes so it will be resolved synchronously.
      def detect_unsafe_proxy_usage(body_node)
        proxy_vars = build_proxy_var_map(body_node)
        return Set.new if proxy_vars.empty?

        unsafe_classes = Set.new
        scan_for_unsafe_usage(body_node, proxy_vars, unsafe_classes)
        unsafe_classes
      end

      # Build mapping of { local_var_name => dep_class } from assignment statements
      def build_proxy_var_map(body_node)
        proxy_vars = {}
        return proxy_vars unless body_node.is_a?(Prism::StatementsNode)

        body_node.body.each do |stmt|
          next unless stmt.is_a?(Prism::LocalVariableWriteNode)

          dep_class = extract_dep_class(stmt.value)
          proxy_vars[stmt.name] = dep_class if dep_class
        end
        proxy_vars
      end

      # Extract the dep class from a call node if it's a Taski::Task dep call
      def extract_dep_class(node)
        return nil unless node.is_a?(Prism::CallNode)
        return nil unless node.receiver

        case node.receiver
        when Prism::ConstantReadNode, Prism::ConstantPathNode
          constant_name = node.receiver.slice
          resolved = resolve_constant(constant_name)
          if resolved.is_a?(Class) && defined?(Taski::Task) && resolved < Taski::Task
            resolved
          end
        end
      end

      # Recursively scan AST for unsafe proxy variable usage.
      # Safe contexts: receiver of CallNode, string interpolation,
      # RHS of local/ivar assignment. Everything else is unsafe.
      def scan_for_unsafe_usage(node, proxy_vars, unsafe_classes) # rubocop:disable Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
        case node
        when Prism::StatementsNode
          node.body.each { |child| scan_for_unsafe_usage(child, proxy_vars, unsafe_classes) }

        when Prism::LocalVariableWriteNode
          if node.value.is_a?(Prism::LocalVariableReadNode) && proxy_vars.key?(node.value.name)
            # Reassignment: track the new variable name too
            proxy_vars[node.name] = proxy_vars[node.value.name]
          else
            scan_for_unsafe_usage(node.value, proxy_vars, unsafe_classes)
          end

        when Prism::InstanceVariableWriteNode
          if node.value.is_a?(Prism::LocalVariableReadNode) && proxy_vars.key?(node.value.name)
            # @x = proxy → safe (resolve_proxy_exports handles it)
          else
            scan_for_unsafe_usage(node.value, proxy_vars, unsafe_classes)
          end

        when Prism::CallNode
          # Receiver: proxy.foo → safe (method_missing fires)
          if node.receiver.is_a?(Prism::LocalVariableReadNode) && proxy_vars.key?(node.receiver.name)
            # safe — don't flag receiver
          elsif node.receiver
            scan_for_unsafe_usage(node.receiver, proxy_vars, unsafe_classes)
          end
          # Arguments: foo(proxy) → UNSAFE
          node.arguments&.arguments&.each do |arg|
            if arg.is_a?(Prism::LocalVariableReadNode) && proxy_vars.key?(arg.name)
              unsafe_classes.add(proxy_vars[arg.name])
            else
              scan_for_unsafe_usage(arg, proxy_vars, unsafe_classes)
            end
          end
          scan_for_unsafe_usage(node.block, proxy_vars, unsafe_classes) if node.block

        when Prism::IfNode
          check_predicate_unsafe(node.predicate, proxy_vars, unsafe_classes)
          scan_for_unsafe_usage(node.statements, proxy_vars, unsafe_classes) if node.statements
          scan_for_unsafe_usage(node.subsequent, proxy_vars, unsafe_classes) if node.subsequent

        when Prism::UnlessNode
          check_predicate_unsafe(node.predicate, proxy_vars, unsafe_classes)
          scan_for_unsafe_usage(node.statements, proxy_vars, unsafe_classes) if node.statements
          scan_for_unsafe_usage(node.else_clause, proxy_vars, unsafe_classes) if node.else_clause

        when Prism::WhileNode, Prism::UntilNode
          check_predicate_unsafe(node.predicate, proxy_vars, unsafe_classes)
          scan_for_unsafe_usage(node.statements, proxy_vars, unsafe_classes) if node.statements

        when Prism::InterpolatedStringNode
          node.parts.each do |part|
            next unless part.is_a?(Prism::EmbeddedStatementsNode)

            if part.statements&.body&.size == 1 &&
                part.statements.body[0].is_a?(Prism::LocalVariableReadNode) &&
                proxy_vars.key?(part.statements.body[0].name)
              # safe — string interpolation calls to_s
            else
              scan_for_unsafe_usage(part, proxy_vars, unsafe_classes)
            end
          end

        when Prism::EmbeddedStatementsNode
          scan_for_unsafe_usage(node.statements, proxy_vars, unsafe_classes) if node.statements

        when Prism::ArrayNode
          node.elements.each do |elem|
            if elem.is_a?(Prism::LocalVariableReadNode) && proxy_vars.key?(elem.name)
              unsafe_classes.add(proxy_vars[elem.name])
            else
              scan_for_unsafe_usage(elem, proxy_vars, unsafe_classes)
            end
          end

        when Prism::ElseNode
          scan_for_unsafe_usage(node.statements, proxy_vars, unsafe_classes) if node.statements

        when Prism::BeginNode
          scan_for_unsafe_usage(node.statements, proxy_vars, unsafe_classes) if node.statements
          scan_for_unsafe_usage(node.rescue_clause, proxy_vars, unsafe_classes) if node.rescue_clause
          scan_for_unsafe_usage(node.ensure_clause, proxy_vars, unsafe_classes) if node.ensure_clause

        when Prism::RescueNode
          scan_for_unsafe_usage(node.statements, proxy_vars, unsafe_classes) if node.statements
          scan_for_unsafe_usage(node.subsequent, proxy_vars, unsafe_classes) if node.subsequent

        when Prism::EnsureNode
          scan_for_unsafe_usage(node.statements, proxy_vars, unsafe_classes) if node.statements

        when Prism::ParenthesesNode
          scan_for_unsafe_usage(node.body, proxy_vars, unsafe_classes) if node.body

        when Prism::LocalVariableReadNode
          # Bare proxy variable read in unknown context → UNSAFE
          unsafe_classes.add(proxy_vars[node.name]) if proxy_vars.key?(node.name)

        else
          # For any unhandled node type, recurse into children (safety-first)
          if node.respond_to?(:compact_child_nodes)
            node.compact_child_nodes.each do |child|
              scan_for_unsafe_usage(child, proxy_vars, unsafe_classes)
            end
          end
        end
      end

      # Check if a predicate node is an unsafe proxy variable read
      def check_predicate_unsafe(predicate, proxy_vars, unsafe_classes)
        if predicate.is_a?(Prism::LocalVariableReadNode) && proxy_vars.key?(predicate.name)
          unsafe_classes.add(proxy_vars[predicate.name])
        else
          scan_for_unsafe_usage(predicate, proxy_vars, unsafe_classes)
        end
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
