# frozen_string_literal: true

require_relative "dependency_analyzer"
require_relative "tree_display"
require_relative "task_interface"

module Taski
  # Section provides an interface abstraction layer for dynamic implementation selection
  # while maintaining static analysis capabilities
  class Section
    extend TaskInterface::ClassMethods

    class << self
      # === Dependency Resolution ===

      # Analyze dependencies when accessing interface methods
      def analyze_dependencies_for_interfaces
        interface_exports.each do |interface_method|
          dependencies = gather_static_dependencies_for_interface(interface_method)
          add_unique_dependencies(dependencies)
        end
      end

      private

      # Gather dependencies from interface method implementation
      def gather_static_dependencies_for_interface(interface_method)
        # For sections, we analyze the impl method
        # Try instance method first, then class method
        if impl_defined?
          # For instance method, we can't analyze dependencies statically
          # So we return empty array
          []
        else
          DependencyAnalyzer.analyze_method(self, :impl)
        end
      end

      public

      # === Instance Management (minimal for Section) ===

      # Ensure section is available (no actual building needed)
      # @return [self] Returns self for compatibility with Task interface
      def ensure_instance_built
        self
      end

      # Run method for sections (Section doesn't run instances)
      # @param args [Hash] Optional arguments (ignored for sections)
      # @return [self] Returns self
      def run(**args)
        self
      end

      # Build method for compatibility (Section doesn't build instances)
      alias_method :build, :run

      # Reset method for compatibility (Section doesn't have state to reset)
      # @return [self] Returns self
      def reset!
        self
      end

      # Display dependency tree for this section
      # @param prefix [String] Current indentation prefix
      # @param visited [Set] Set of visited classes to prevent infinite loops
      # @param color [Boolean] Whether to use color output
      # @return [String] Formatted dependency tree
      def tree(prefix = "", visited = Set.new, color: Taski::TreeDisplay::TreeColors.enabled?)
        should_return_early, early_result, new_visited = handle_circular_dependency_check(visited, self, prefix)
        return early_result if should_return_early

        # Get section name with fallback for anonymous classes
        section_name = name || to_s
        colored_section_name = color ? Taski::TreeDisplay::TreeColors.section(section_name) : section_name
        result = "#{prefix}#{colored_section_name}\n"

        # Add possible implementations - detect from nested Task classes
        possible_implementations = find_possible_implementations
        if possible_implementations.any?
          impl_names = possible_implementations.map { |impl| extract_implementation_name(impl) }
          impl_text = "[One of: #{impl_names.join(", ")}]"
          colored_impl_text = color ? Taski::TreeDisplay::TreeColors.implementations(impl_text) : impl_text
          connector = color ? Taski::TreeDisplay::TreeColors.connector("└── ") : "└── "
          result += "#{prefix}#{connector}#{colored_impl_text}\n"
        end

        dependencies = @dependencies || []
        result += render_dependencies_tree(dependencies, prefix, new_visited, color)

        result
      end

      # Define interface methods for this section
      def interface(*names)
        if names.empty?
          raise ArgumentError, "interface requires at least one method name"
        end

        @interface_exports = names

        # Create accessor methods for each interface name
        names.each do |name|
          define_singleton_method(name) do
            # Get implementation class
            implementation_class = get_implementation_class

            # Check if implementation is nil
            if implementation_class.nil?
              raise SectionImplementationError,
                "impl returned nil. " \
                "Make sure impl returns a Task class."
            end

            # Validate that it's a Task class
            unless implementation_class.is_a?(Class) && implementation_class < Taski::Task
              raise SectionImplementationError,
                "impl must return a Task class, got #{implementation_class.class}. " \
                "Make sure impl returns a class that inherits from Taski::Task."
            end

            # Build the implementation and call the method
            implementation = implementation_class.run

            begin
              implementation.public_send(name)
            rescue NoMethodError
              raise SectionImplementationError,
                "Implementation does not provide required method '#{name}'. " \
                "Make sure the implementation class has a '#{name}' method or " \
                "exports :#{name} declaration."
            end
          end
        end

        # Automatically apply exports to existing nested Task classes
        auto_apply_exports_to_existing_tasks
      end

      # Get the interface exports for this section
      def interface_exports
        @interface_exports || []
      end

      # Check if impl method is defined (as instance method)
      def impl_defined?
        instance_methods(false).include?(:impl)
      end

      # Get implementation class from instance method
      def get_implementation_class
        if impl_defined?
          # Create a temporary instance to call impl method
          instance = allocate
          # Call the impl method on the instance
          instance.impl
        else
          # Fall back to class method if exists
          impl
        end
      end

      # Override const_set to auto-add exports to nested Task classes
      def const_set(name, value)
        result = super

        # If the constant is a Task class and we have interface exports,
        # automatically add exports to avoid duplication
        if value.is_a?(Class) && value < Taski::Task && !interface_exports.empty?
          # Add exports declaration to the nested task
          exports_list = interface_exports
          value.class_eval do
            exports(*exports_list)
          end
        end

        result
      end

      private

      # Automatically apply exports to existing nested Task classes when interface is defined
      def auto_apply_exports_to_existing_tasks
        constants.each do |const_name|
          const_value = const_get(const_name)
          if const_value.is_a?(Class) && const_value < Taski::Task && !interface_exports.empty?
            exports_list = interface_exports
            const_value.class_eval do
              exports(*exports_list) unless @exports_defined
              @exports_defined = true
            end
          end
        end
      end

      # Find possible implementation classes by scanning nested Task classes
      def find_possible_implementations
        task_classes = []
        constants.each do |const_name|
          const_value = const_get(const_name)
          if task_class?(const_value)
            task_classes << const_value
          end
        end
        task_classes
      end

      # Extract readable name from implementation class
      def extract_implementation_name(impl_class)
        class_name = impl_class.name
        return impl_class.to_s unless class_name&.include?("::")

        class_name.split("::").last
      end

      # Check if a constant value is a Task class
      def task_class?(const_value)
        const_value.is_a?(Class) && const_value < Taski::Task
      end

      include TreeDisplay

      # Subclasses should override this method to select appropriate implementation
      def impl
        raise NotImplementedError, "Subclass must implement impl"
      end
    end
  end
end
