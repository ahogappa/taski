# frozen_string_literal: true

require_relative "exceptions"

module Taski
  # Reference class for task references
  #
  # Used to create lazy references to task classes by name,
  # which is useful for dependency tracking and metaprogramming.
  class Reference
    attr_reader :klass

    # @param klass [String] The name of the class to reference
    def initialize(klass)
      @klass = klass
    end

    # Dereference to get the actual class object
    # @return [Class] The referenced class
    # @raise [TaskAnalysisError] If the constant cannot be resolved
    def deref
      Object.const_get(@klass)
    rescue NameError => e
      raise TaskAnalysisError, "Cannot resolve constant '#{@klass}': #{e.message}"
    end

    # Compare reference with another object
    # @param other [Object] Object to compare with
    # @return [Boolean] True if the referenced class equals the other object
    def ==(other)
      Object.const_get(@klass) == other
    rescue NameError
      false
    end

    # String representation of the reference
    # @return [String] Reference representation
    def inspect
      "&#{@klass}"
    end
  end
end
