# frozen_string_literal: true

require "prism"
require_relative "visitor"

module Taski
  module StaticAnalysis
    # Analyzes task dependencies using static analysis of source code
    class Analyzer
      # Analyze dependencies for a given task class
      #
      # @param task_class [Class] The task class to analyze
      # @return [Set<Class>] Set of task classes that are dependencies
      def self.analyze(task_class)
        source_location = extract_run_method_location(task_class)
        return Set.new unless source_location

        file_path, _line_number = source_location
        parse_result = Prism.parse_file(file_path)

        visitor = Visitor.new(task_class)
        visitor.visit(parse_result.value)
        visitor.dependencies
      end

      # Extract the source location of the run method
      #
      # @param task_class [Class] The task class
      # @return [Array<String, Integer>, nil] File path and line number, or nil
      def self.extract_run_method_location(task_class)
        task_class.instance_method(:run).source_location
      rescue NameError
        nil
      end

      private_class_method :extract_run_method_location
    end
  end
end
