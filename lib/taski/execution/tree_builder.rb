# frozen_string_literal: true

module Taski
  module Execution
    # Shared tree traversal logic for building dependency trees.
    # Used by both StaticTreeRenderer and TreeProgressDisplay to build
    # consistent tree structures from task dependency graphs.
    #
    # Each dependency metadata hash contains:
    #   - :task_class [Class] - The dependency task class
    #   - :is_section [Boolean] - Whether the dependency is a Section
    #   - :is_circular [Boolean] - Whether this creates a circular reference
    #   - :is_impl_candidate [Boolean] - Whether this is an impl candidate for a Section
    module TreeBuilder
      class << self
        # Build an array of dependency metadata for a task class.
        # Handles circular reference detection and impl candidate identification.
        #
        # @param task_class [Class] The task class to analyze dependencies for
        # @param ancestors [Set] Set of ancestor task classes for circular detection
        # @return [Array<Hash>] Array of dependency metadata hashes
        def build_dependencies(task_class, ancestors = Set.new)
          dependencies = StaticAnalysis::Analyzer.analyze(task_class).to_a
          is_parent_section = section_class?(task_class)

          dependencies.map do |dep|
            is_circular = ancestors.include?(dep)
            is_impl = detect_impl_candidate(dep, task_class, is_parent_section)

            {
              task_class: dep,
              is_section: section_class?(dep),
              is_circular: is_circular,
              is_impl_candidate: is_impl
            }
          end
        end

        # Check if a class is a Section.
        #
        # @param klass [Class] The class to check
        # @return [Boolean] true if the class inherits from Taski::Section
        def section_class?(klass)
          defined?(Taski::Section) && klass < Taski::Section
        end

        # Check if a child class is nested inside a parent class.
        # Used to determine impl candidates for Sections.
        #
        # @param child_class [Class] The potential nested class
        # @param parent_class [Class] The potential parent class
        # @return [Boolean] true if child_class is nested inside parent_class
        def nested_class?(child_class, parent_class)
          child_name = child_class.name.to_s
          parent_name = parent_class.name.to_s
          child_name.start_with?("#{parent_name}::")
        end

        # Determine if a dependency is an impl candidate for a Section.
        # A dependency is an impl candidate if:
        #   1. The parent is a Section
        #   2. The dependency is a nested class of the parent
        #
        # @param dependency [Class] The dependency task class
        # @param parent_task_class [Class] The parent task class
        # @param is_parent_section [Boolean] Whether the parent is a Section (optional optimization)
        # @return [Boolean] true if the dependency is an impl candidate
        def detect_impl_candidate(dependency, parent_task_class, is_parent_section = nil)
          is_parent_section = section_class?(parent_task_class) if is_parent_section.nil?
          is_parent_section && nested_class?(dependency, parent_task_class)
        end
      end
    end
  end
end
