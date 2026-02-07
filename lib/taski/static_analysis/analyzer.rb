# frozen_string_literal: true

require "prism"
require_relative "visitor"

module Taski
  module StaticAnalysis
    class Analyzer
      # Analyzes a task class and returns its static dependencies.
      # Dependencies are detected from the run method and called methods (SomeTask.method calls).
      #
      # Static dependencies are used for:
      # - Tree display visualization
      # - Circular dependency detection
      # - Task execution ordering
      #
      # @param task_class [Class] The task class to analyze
      # @return [Set<Class>] Set of task classes that are static dependencies
      def self.analyze(task_class)
        source_location = extract_method_location(task_class, :run)
        return Set.new unless source_location

        file_path, _line_number = source_location
        parse_result = Prism.parse_file(file_path)

        visitor = Visitor.new(task_class, :run)
        visitor.visit(parse_result.value)
        # Follow method calls to analyze dependencies in called methods
        visitor.follow_method_calls
        visitor.dependencies
      end

      # @param task_class [Class] The task class
      # @param method_name [Symbol] The method name to extract location for
      # @return [Array<String, Integer>, nil] File path and line number, or nil
      def self.extract_method_location(task_class, method_name)
        task_class.instance_method(method_name).source_location
      rescue NameError
        nil
      end

      private_class_method :extract_method_location
    end
  end
end
