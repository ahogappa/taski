# frozen_string_literal: true

module Taski
  # Common utility functions for the Taski framework
  module Utils
    # Handle circular dependency error message generation
    module CircularDependencyHelpers
      # Build detailed error message for circular dependencies
      # @param cycle_path [Array<Class>] The circular dependency path
      # @param context [String] Context of the error (dependency, runtime)
      # @return [String] Formatted error message
      def self.build_error_message(cycle_path, context = "dependency")
        path_names = cycle_path.map { |klass| klass.name || klass.to_s }

        message = "Circular dependency detected!\n"
        message += "Cycle: #{path_names.join(" → ")}\n\n"
        message += "The #{context} chain is:\n"

        cycle_path.each_cons(2).with_index do |(from, to), index|
          action = (context == "dependency") ? "depends on" : "is trying to build"
          message += "  #{index + 1}. #{from.name} #{action} → #{to.name}\n"
        end

        message += "\nThis creates an infinite loop that cannot be resolved." if context == "dependency"
        message
      end
    end

    # Common dependency utility functions
    module DependencyUtils
      # Extract class from dependency hash
      # @param dep [Hash] Dependency information
      # @return [Class] The dependency class
      def extract_class(dep)
        klass = dep[:klass]
        klass.is_a?(Reference) ? klass.deref : klass
      end
    end

    # Common task build utility functions
    module TaskBuildHelpers
      # Execute block with comprehensive build logging
      # @param task_name [String] Name of the task being built
      # @param dependencies [Array] List of dependencies
      # @param args [Hash] Build arguments for parametrized builds
      # @yield Block to execute with logging
      # @return [Object] Result of the block execution
      def self.with_build_logging(task_name, dependencies: [], args: nil)
        build_start_time = Time.now

        begin
          Taski.logger.task_build_start(task_name, dependencies: dependencies, args: args)
          result = yield
          duration = Time.now - build_start_time
          Taski.logger.task_build_complete(task_name, duration: duration)
          result
        rescue => e
          duration = Time.now - build_start_time
          Taski.logger.task_build_failed(task_name, error: e, duration: duration)
          error_message = "Failed to build task #{task_name}"
          error_message += " with args #{args}" if args && !args.empty?
          error_message += ": #{e.message}"
          raise TaskBuildError, error_message
        end
      end
    end
  end
end
