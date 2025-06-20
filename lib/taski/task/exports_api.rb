# frozen_string_literal: true

module Taski
  class Task
    class << self
      # === Exports API ===
      # Export instance variables as class methods for static dependencies

      # Export instance variables as both class and instance methods
      # @param names [Array<Symbol>] Names of instance variables to export
      def exports(*names)
        @exports ||= []
        @exports += names

        names.each do |name|
          next if respond_to?(name)

          # Define class method to access exported value
          define_singleton_method(name) do
            ensure_instance_built.send(name)
          end

          # Define instance method getter
          define_method(name) do
            instance_variable_get("@#{name}")
          end
        end
      end
    end
  end
end
