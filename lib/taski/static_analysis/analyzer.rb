# frozen_string_literal: true

require "prism"
require_relative "visitor"

module Taski
  module StaticAnalysis
    class Analyzer
      # Analyzes a task class and returns its static dependencies.
      # For Task: dependencies detected from run method (SomeTask.method calls)
      # For Section: impl candidates detected from impl method (constants returned)
      #
      # Static dependencies are used for:
      # - Tree display visualization
      # - Circular dependency detection
      # - Task execution (for Task only; Section resolves impl at runtime)
      #
      # @param task_class [Class] The task class to analyze
      # @return [Set<Class>] Set of task classes that are static dependencies
      def self.analyze(task_class)
        target_method = target_method_for(task_class)
        source_location = extract_method_location(task_class, target_method)
        return Set.new unless source_location

        file_path, _line_number = source_location
        parse_result = Prism.parse_file(file_path)

        visitor = Visitor.new(task_class, target_method)
        visitor.visit(parse_result.value)
        visitor.dependencies
      end

      # @param task_class [Class] The task class
      # @return [Symbol] The method name to analyze (:run for Task, :impl for Section)
      def self.target_method_for(task_class)
        if defined?(Taski::Section) && task_class < Taski::Section
          :impl
        else
          :run
        end
      end

      # @param task_class [Class] The task class
      # @param method_name [Symbol] The method name to extract location for
      # @return [Array<String, Integer>, nil] File path and line number, or nil
      def self.extract_method_location(task_class, method_name)
        task_class.instance_method(method_name).source_location
      rescue NameError
        nil
      end

      private_class_method :target_method_for, :extract_method_location
    end
  end
end
