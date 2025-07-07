# frozen_string_literal: true

module Taski
  # Circular dependency detection logic extracted from instance_management
  class CircularDependencyDetector
    include TaskComponent

    def check_circular_dependency
      thread_key = build_thread_key
      if Thread.current[thread_key]
        handle_circular_dependency_detected
      end
    end

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

    private

    # Handle the case when circular dependency is detected
    # @raise [CircularDependencyError] Always raises with detailed message
    def handle_circular_dependency_detected
      # Build dependency path for better error message
      cycle_path = build_current_dependency_path
      raise CircularDependencyError, build_runtime_circular_dependency_message(cycle_path)
    end

    # Build current dependency path from thread-local storage
    # @return [Array<Class>] Array of classes in the current build path
    def build_current_dependency_path
      path = []
      Thread.current.keys.each do |key|
        if key.to_s.end_with?(Taski::Task::THREAD_KEY_SUFFIX) && Thread.current[key]
          class_name = key.to_s.sub(Taski::Task::THREAD_KEY_SUFFIX, "")
          begin
            path << Object.const_get(class_name)
          rescue NameError
            # Skip if class not found
          end
        end
      end
      path << @task_class
    end

    # Build runtime circular dependency error message
    # @param cycle_path [Array<Class>] The circular dependency path
    # @return [String] Formatted error message
    def build_runtime_circular_dependency_message(cycle_path)
      self.class.build_error_message(cycle_path, "runtime")
    end
  end
end
