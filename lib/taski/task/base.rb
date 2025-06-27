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

      # Display dependency tree for this task
      # @param prefix [String] Current indentation prefix
      # @param visited [Set] Set of visited classes to prevent infinite loops
      # @return [String] Formatted dependency tree
      def tree(prefix = "", visited = Set.new)
        return "#{prefix}#{name} (circular)\n" if visited.include?(self)

        visited = visited.dup
        visited << self

        result = "#{prefix}#{name}\n"

        dependencies = (@dependencies || []).uniq { |dep| extract_class(dep) }
        dependencies.each_with_index do |dep, index|
          dep_class = extract_class(dep)
          is_last = index == dependencies.length - 1

          connector = is_last ? "└── " : "├── "
          child_prefix = prefix + (is_last ? "    " : "│   ")

          # For the dependency itself, we want to use the connector
          # For its children, we want to use the child_prefix
          dep_tree = dep_class.tree(child_prefix, visited)
          # Replace the first line (which has child_prefix) with the proper connector
          dep_lines = dep_tree.lines
          if dep_lines.any?
            # Replace the first line prefix with connector
            first_line = dep_lines[0]
            fixed_first_line = first_line.sub(/^#{Regexp.escape(child_prefix)}/, prefix + connector)
            result += fixed_first_line
            # Add the rest of the lines as-is
            result += dep_lines[1..-1].join if dep_lines.length > 1
          else
            result += "#{prefix}#{connector}#{dep_class.name}\n"
          end
        end

        result
      end

      private

      include Utils::DependencyUtils
      private :extract_class
    end

    # === Instance Methods ===

    # Build method that must be implemented by subclasses
    # @raise [NotImplementedError] If not implemented by subclass
    def build
      raise NotImplementedError, "You must implement the build method in your task class"
    end

    # Access build arguments passed to parametrized builds
    # @return [Hash] Build arguments or empty hash if none provided
    def build_args
      @build_args || {}
    end

    # Clean method with default empty implementation
    # Subclasses can override this method to implement cleanup logic
    def clean
      # Default implementation does nothing
    end
  end
end
