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
          next if respond_to?(name)

          # Define class method that delegates to instance
          define_singleton_method(name) do
            ensure_instance_built.public_send(name)
          end

          # Define instance method - use attr_reader for basic identifiers only
          if name.to_s.match?(/\A[a-zA-Z_][a-zA-Z0-9_]*\z/)
            attr_reader name
          else
            # TECHNICAL DEBT: Special characters (?, !) require instance_variable_get
            # TODO: Replace with Hash-based state management in future refactoring
            define_method(name) do
              instance_variable_get("@#{name}")
            end
          end
        end
      end
    end
  end
end
