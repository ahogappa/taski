# frozen_string_literal: true

require_relative "../exceptions"

module Taski
  # Base Task class that provides the foundation for task framework
  # This module contains the core constants and basic structure
  class Task
    # Constants for thread-local keys and method tracking
    THREAD_KEY_SUFFIX = "_building"
    TASKI_ANALYZING_DEFINE_KEY = :taski_analyzing_define
    ANALYZED_METHODS = [:build, :clean].freeze

    class << self
      # === Hook Methods ===

      # Hook called when build/clean methods are defined
      # This triggers static analysis of dependencies
      def method_added(method_name)
        super
        return unless ANALYZED_METHODS.include?(method_name)
        # Only call if the method is available (loaded by dependency_resolver)
        analyze_dependencies_at_definition if respond_to?(:analyze_dependencies_at_definition, true)
      end

      # Create a reference to a task class (can be used anywhere)
      # @param klass [String] The class name to reference
      # @return [Reference] A reference object
      def ref(klass)
        reference = Reference.new(klass)
        # If we're in a define context, throw for dependency tracking
        if Thread.current[TASKI_ANALYZING_DEFINE_KEY]
          reference.tap { |ref| throw :unresolved, ref }
        else
          reference
        end
      end

      # Get or create resolution state for define API
      # @return [Hash] Resolution state hash
      def __resolve__
        @__resolve__ ||= {}
      end
    end

    # === Instance Methods ===

    # Build method that must be implemented by subclasses
    # @raise [NotImplementedError] If not implemented by subclass
    def build
      raise NotImplementedError, "You must implement the build method in your task class"
    end

    # Clean method with default empty implementation
    # Subclasses can override this method to implement cleanup logic
    def clean
      # Default implementation does nothing
    end
  end
end
