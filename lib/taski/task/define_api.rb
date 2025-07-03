# frozen_string_literal: true

module Taski
  class Task
    class << self
      # === Define API ===
      # Define lazy-evaluated values with dynamic dependency resolution

      # Define a lazy-evaluated value using a block
      # Use this API when dependencies change based on runtime conditions,
      # environment-specific configurations, feature flags, or complex conditional logic
      # @param name [Symbol] Name of the value
      # @param block [Proc] Block that computes the value and determines dependencies at runtime
      # @param options [Hash] Additional options
      def define(name, block, **options)
        @dependencies ||= []
        @definitions ||= {}

        # Create method that tracks dependencies on first call
        create_tracking_method(name)

        # Analyze dependencies by executing the block
        dependencies = analyze_define_dependencies(block)

        @dependencies += dependencies
        @definitions[name] = {block:, options:, classes: dependencies}
      end

      private

      # === Define API Implementation ===

      # Create method that tracks dependencies for define API
      # @param name [Symbol] Method name to create
      def create_tracking_method(name)
        # Only create tracking method during dependency analysis
        class_eval(<<-RUBY, __FILE__, __LINE__ + 1)
          def self.#{name}
            resolution_state[__callee__] ||= false
            if resolution_state[__callee__]
              # already resolved - prevents infinite recursion
            else
              resolution_state[__callee__] = true
              throw :unresolved, [self, __callee__]
            end
          end
        RUBY
      end

      # Analyze dependencies in define block
      # @param block [Proc] Block to analyze
      # @return [Array<Hash>] Array of dependency information
      def analyze_define_dependencies(block)
        classes = []
        seen_refs = Set.new

        # Set flag to indicate we're analyzing define dependencies
        Thread.current[TASKI_ANALYZING_DEFINE_KEY] = true

        loop do
          klass, task = catch(:unresolved) do
            block.call
            nil
          end

          break if klass.nil?

          # Track pending references for phase 2 resolution
          if klass.is_a?(Taski::Reference)
            ref_key = klass.klass

            # Skip if we've already seen this reference
            break if seen_refs.include?(ref_key)

            seen_refs << ref_key
            add_pending_reference(ref_key)
          end

          classes << {klass:, task:}
        end

        # Reset resolution state
        classes.each do |task_class|
          klass = task_class[:klass]
          # Reference objects are stateless but Task classes store analysis state
          # Selective reset prevents errors while ensuring clean state for next analysis
          if klass.respond_to?(:instance_variable_set) && !klass.is_a?(Taski::Reference)
            klass.instance_variable_set(:@__resolution_state, {})
          end
        end

        classes
      ensure
        Thread.current[TASKI_ANALYZING_DEFINE_KEY] = false
      end

      # Create methods for values defined with define API
      def create_defined_methods
        @definitions ||= {}
        @definitions.each do |name, definition|
          create_defined_method(name, definition) unless method_defined_for_define?(name)
        end
      end

      # Create a single defined method (both class and instance)
      # @param name [Symbol] Method name
      # @param definition [Hash] Method definition information
      def create_defined_method(name, definition)
        # Remove tracking method first to avoid redefinition warnings
        singleton_class.undef_method(name) if singleton_class.method_defined?(name)

        # Class method with lazy evaluation
        define_singleton_method(name) do
          @__defined_values ||= {}
          @__defined_values[name] ||= definition[:block].call
        end

        # Instance method that delegates to class method
        define_method(name) do
          @__defined_values ||= {}
          @__defined_values[name] ||= self.class.send(name)
        end

        # Mark as defined for this resolution
        mark_method_as_defined(name)
      end

      # Mark method as defined for this resolution cycle
      # @param method_name [Symbol] Method name to mark
      def mark_method_as_defined(method_name)
        @__defined_for_resolve ||= Set.new
        @__defined_for_resolve << method_name
      end

      # Check if method was already defined for define API
      # @param method_name [Symbol] Method name to check
      # @return [Boolean] True if already defined
      def method_defined_for_define?(method_name)
        @__defined_for_resolve ||= Set.new
        @__defined_for_resolve.include?(method_name)
      end

      # Get all pending references for this class (public for testing)
      def get_pending_references
        @pending_references ||= Set.new
      end

      # Override base class implementation to validate ref() calls
      # This is called during phase 2 before dependency resolution
      def resolve_pending_references
        pending_refs = get_pending_references
        return if pending_refs.empty?

        pending_refs.each do |klass_name|
          Object.const_get(klass_name)
        rescue NameError => e
          task_name = name || to_s
          raise Taski::TaskAnalysisError, "Task '#{task_name}' cannot resolve ref('#{klass_name}'): #{e.message}"
        end
      end

      # Track pending references for phase 2 resolution (public for debugging)
      def add_pending_reference(klass_name)
        @pending_references ||= Set.new
        @pending_references << klass_name
      end
    end
  end
end
