# frozen_string_literal: true

require_relative "task"

module Taski
  # Base class for sections with dynamic implementation selection
  class Section < Task
    class << self
      # Define interface methods (alias for exports)
      #
      # @param interface_methods [Array<Symbol>] Names of interface methods
      def interfaces(*interface_methods)
        exports(*interface_methods)
      end
    end

    # Run the section by delegating to the implementation
    def run
      implementation_class = impl
      unless implementation_class
        raise "Section #{self.class} does not have an implementation. Override 'impl' method."
      end

      # Apply interface to implementation class before execution
      apply_interface_to_implementation(implementation_class)

      # Copy all exported values from the implementation class to this section
      # The implementation class methods are automatically triggered by accessing them
      self.class.exported_methods.each do |method|
        value = implementation_class.public_send(method)
        # NOTE: Using instance_variable_set is unavoidable here for storing
        # values from the implementation. This is part of the section delegation pattern.
        instance_variable_set("@#{method}", value)
      end
    end

    # Get the implementation class (must be overridden by subclasses)
    #
    # @return [Class] The implementation task class
    # @raise [NotImplementedError] If not implemented by subclass
    def impl
      raise NotImplementedError, "Subclasses must implement the impl method to return implementation class"
    end

    private

    # Apply the section's interface methods to the implementation class
    #
    # @param implementation_class [Class] The implementation task class
    def apply_interface_to_implementation(implementation_class)
      interface_methods = self.class.exported_methods
      return if interface_methods.empty?

      implementation_class.exports(*interface_methods)
    end
  end
end
