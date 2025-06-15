# frozen_string_literal: true

require 'set'

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
        @definitions[name] = { block:, options:, classes: dependencies }
      end

      private

      # === Define API Implementation ===

      # Create method that tracks dependencies for define API
      # @param name [Symbol] Method name to create
      def create_tracking_method(name)
        class_eval(<<-RUBY, __FILE__, __LINE__ + 1)
          def self.#{name}
            __resolve__[__callee__] ||= false
            if __resolve__[__callee__]
              # already resolved
            else
              __resolve__[__callee__] = true
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

        # Set flag to indicate we're analyzing define dependencies
        Thread.current[TASKI_ANALYZING_DEFINE_KEY] = true

        loop do
          klass, task = catch(:unresolved) do
            block.call
            nil
          end

          break if klass.nil?

          classes << { klass:, task: }
        end

        # Reset resolution state
        classes.each do |task_class|
          task_class[:klass].instance_variable_set(:@__resolve__, {})
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
    end
  end
end