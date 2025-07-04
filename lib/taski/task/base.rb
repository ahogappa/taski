# frozen_string_literal: true

require_relative "../exceptions"
require_relative "../utils/tree_display"

module Taski
  # Base Task class that provides the foundation for task framework
  # This module contains the core constants and basic structure
  class Task
    # Constants for thread-local keys and method tracking
    THREAD_KEY_SUFFIX = "_building"
    TASKI_ANALYZING_DEFINE_KEY = :taski_analyzing_define
    ANALYZED_METHODS = [:build, :clean, :run].freeze

    class << self
      # === Hook Methods ===

      # Hook called when build/clean methods are defined
      # This triggers static analysis of dependencies
      def method_added(method_name)
        super
        return unless ANALYZED_METHODS.include?(method_name)
        # Avoid calling before dependency_resolver module is loaded
        analyze_dependencies_at_definition if respond_to?(:analyze_dependencies_at_definition, true)
      end

      # Create a reference to a task class (can be used anywhere)
      # @param klass [String] The class name to reference
      # @return [Reference, Class] A reference object or actual class
      def ref(klass_name)
        # During dependency analysis, track as dependency but defer resolution
        if Thread.current[TASKI_ANALYZING_DEFINE_KEY]
          # Create Reference object for deferred resolution
          reference = Reference.new(klass_name)
          # Track as dependency by throwing unresolved
          throw :unresolved, [reference, :deref]
        else
          # At runtime, try to resolve to actual class for convenience
          # This provides better ergonomics for define API usage
          begin
            Object.const_get(klass_name)
          rescue NameError
            # Fall back to Reference object if class doesn't exist yet
            # This maintains compatibility with forward references
            Reference.new(klass_name)
          end
        end
      end

      # Get or create resolution state for define API
      # @return [Hash] Resolution state hash
      def resolution_state
        @__resolution_state ||= {}
      end

      # Default implementation of resolve_pending_references
      # This does nothing by default, but DefineAPI overrides it
      # to validate ref() calls collected during analysis
      def resolve_pending_references
        # No-op for tasks that don't use DefineAPI
      end

      # Display dependency tree for this task
      # @param prefix [String] Current indentation prefix
      # @param visited [Set] Set of visited classes to prevent infinite loops
      # @return [String] Formatted dependency tree
      def tree(prefix = "", visited = Set.new, color: TreeColors.enabled?)
        should_return_early, early_result, new_visited = handle_circular_dependency_check(visited, self, prefix)
        return early_result if should_return_early

        task_name = color ? TreeColors.task(name) : name
        result = "#{prefix}#{task_name}\n"

        dependencies = @dependencies || []
        result += render_dependencies_tree(dependencies, prefix, new_visited, color)

        result
      end

      private

      include Utils::DependencyUtils
      include Utils::TreeDisplay
    end

    # === Instance Methods ===

    # Run method that must be implemented by subclasses
    # @raise [NotImplementedError] If not implemented by subclass
    def run
      raise NotImplementedError, "You must implement the run method in your task class"
    end

    # Build method for backward compatibility
    alias_method :build, :run

    # Access run arguments passed to parametrized runs
    # @return [Hash] Run arguments or empty hash if none provided
    def run_args
      @run_args || {}
    end

    # Build arguments alias for backward compatibility
    alias_method :build_args, :run_args

    # Clean method with default empty implementation
    # Subclasses can override this method to implement cleanup logic
    def clean
      # Default implementation does nothing - allows optional cleanup in subclasses
    end
  end
end
