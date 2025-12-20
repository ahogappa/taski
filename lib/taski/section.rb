# frozen_string_literal: true

require_relative "task"

module Taski
  class Section < Task
    class << self
      # @param interface_methods [Array<Symbol>] Names of interface methods
      def interfaces(*interface_methods)
        exports(*interface_methods)
      end

      # Section does not have static dependencies for execution.
      # The impl method is called at runtime to determine the actual implementation.
      # Static dependencies (impl candidates) are only used for tree display and circular detection.
      def cached_dependencies
        Set.new
      end
    end

    def run
      implementation_class = impl
      unless implementation_class
        raise "Section #{self.class} does not have an implementation. Override 'impl' method."
      end

      # Register runtime dependency for clean phase (before register_impl_selection)
      register_runtime_dependency(implementation_class)

      # Register selected impl for progress display
      register_impl_selection(implementation_class)

      apply_interface_to_implementation(implementation_class)

      self.class.exported_methods.each do |method|
        value = implementation_class.public_send(method)
        instance_variable_set("@#{method}", value)
      end
    end

    # @return [Class] The implementation task class
    # @raise [NotImplementedError] If not implemented by subclass
    def impl
      raise NotImplementedError, "Subclasses must implement the impl method to return implementation class"
    end

    private

    # Register the selected implementation as a runtime dependency.
    # This allows the clean phase to include the dynamically selected impl.
    # Handles nil ExecutionContext gracefully.
    #
    # @param impl_class [Class] The selected implementation class
    def register_runtime_dependency(impl_class)
      context = Execution::ExecutionContext.current
      context&.register_runtime_dependency(self.class, impl_class)
    end

    def register_impl_selection(implementation_class)
      context = Execution::ExecutionContext.current
      return unless context

      context.notify_section_impl_selected(self.class, implementation_class)
    end

    # @param implementation_class [Class] The implementation task class
    def apply_interface_to_implementation(implementation_class)
      interface_methods = self.class.exported_methods
      return if interface_methods.empty?

      implementation_class.exports(*interface_methods)
    end
  end
end
