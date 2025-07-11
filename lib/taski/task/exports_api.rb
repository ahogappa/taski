# frozen_string_literal: true

module Taski
  class Task
    # Module for the Exports API - export instance variables as class methods
    module ExportsAPI
      # Export instance variables as both class and instance methods
      # @param names [Array<Symbol>] Names of instance variables to export
      def exports(*names)
        @exports ||= []
        @exports += names

        names.each do |name|
          next if singleton_class.method_defined?(name)

          # Define class method that delegates to instance
          define_singleton_method(name) do
            ensure_instance_built.public_send(name)
          end

          # Define instance method using attr_reader for valid identifiers
          # Skip special characters as they cannot be used as instance variable names
          if name.to_s.match?(/\A[a-zA-Z_][a-zA-Z0-9_]*\z/)
            attr_reader name
          end
        end
      end
    end
  end
end
