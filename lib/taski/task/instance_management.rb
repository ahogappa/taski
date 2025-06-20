# frozen_string_literal: true

require "monitor"

module Taski
  class Task
    class << self
      # === Lifecycle Management ===

      # Build this task and all its dependencies
      def build
        resolve_dependencies.reverse_each do |task_class|
          task_class.ensure_instance_built
        end
      end

      # Clean this task and all its dependencies in reverse order
      def clean
        resolve_dependencies.each do |task_class|
          # Get existing instance or create new one for cleaning
          instance = task_class.instance_variable_get(:@__task_instance) || task_class.new
          instance.clean
        end
      end

      # Reset task instance and cached data to prevent memory leaks
      # @return [self] Returns self for method chaining
      def reset!
        build_monitor.synchronize do
          @__task_instance = nil
          @__defined_values = nil
          @__defined_for_resolve = nil
          clear_thread_local_state
        end
        self
      end

      # Refresh task state (currently just resets)
      # @return [self] Returns self for method chaining
      def refresh
        reset!
      end

      # === Instance Management ===

      # Ensure task instance is built (public because called from build)
      # @return [Task] The built task instance
      def ensure_instance_built
        # Use double-checked locking pattern for thread safety
        return @__task_instance if @__task_instance

        build_monitor.synchronize do
          # Check again after acquiring lock
          return @__task_instance if @__task_instance

          # Prevent infinite recursion using thread-local storage
          thread_key = build_thread_key
          if Thread.current[thread_key]
            # Build dependency path for better error message
            cycle_path = build_current_dependency_path
            raise CircularDependencyError, build_runtime_circular_dependency_message(cycle_path)
          end

          Thread.current[thread_key] = true
          begin
            build_dependencies
            @__task_instance = build_instance
          ensure
            Thread.current[thread_key] = false
          end
        end

        @__task_instance
      end

      private

      # === Core Helper Methods ===

      # Get or create build monitor for thread safety
      # @return [Monitor] Thread-safe monitor object
      def build_monitor
        @__build_monitor ||= Monitor.new
      end

      # Generate thread key for recursion detection
      # @return [String] Thread key for this task
      def build_thread_key
        "#{name}#{THREAD_KEY_SUFFIX}"
      end

      # Build and configure task instance
      # @return [Task] Built task instance
      def build_instance
        instance = new
        build_start_time = Time.now
        begin
          Taski.logger.task_build_start(name.to_s, dependencies: @dependencies || [])
          instance.build
          duration = Time.now - build_start_time
          Taski.logger.task_build_complete(name.to_s, duration: duration)
          instance
        rescue => e
          duration = Time.now - build_start_time
          # Log the error with full context
          Taski.logger.task_build_failed(name.to_s, error: e, duration: duration)
          raise TaskBuildError, "Failed to build task #{name}: #{e.message}"
        end
      end

      # Clear thread-local state for this task
      def clear_thread_local_state
        Thread.current.keys.each do |key|
          Thread.current[key] = nil if key.to_s.include?(build_thread_key)
        end
      end

      # === Dependency Management ===

      # Build all dependencies of this task
      def build_dependencies
        resolve_dependencies

        (@dependencies || []).each do |dep|
          dep_class = extract_class(dep)
          next if dep_class == self

          dep_class.ensure_instance_built if dep_class.respond_to?(:ensure_instance_built)
        end
      end

      # Build current dependency path from thread-local storage
      # @return [Array<Class>] Array of classes in the current build path
      def build_current_dependency_path
        path = []
        Thread.current.keys.each do |key|
          if key.to_s.end_with?(THREAD_KEY_SUFFIX) && Thread.current[key]
            class_name = key.to_s.sub(THREAD_KEY_SUFFIX, "")
            begin
              path << Object.const_get(class_name)
            rescue NameError
              # Skip if class not found
            end
          end
        end
        path << self
      end

      # Build runtime circular dependency error message
      # @param cycle_path [Array<Class>] The circular dependency path
      # @return [String] Formatted error message
      def build_runtime_circular_dependency_message(cycle_path)
        path_names = cycle_path.map { |klass| klass.name || klass.to_s }

        message = "Circular dependency detected!\n"
        message += "Cycle: #{path_names.join(" → ")}\n\n"
        message += "The dependency chain is:\n"

        cycle_path.each_cons(2).with_index do |(from, to), index|
          message += "  #{index + 1}. #{from.name} is trying to build → #{to.name}\n"
        end

        message += "\nThis creates an infinite loop that cannot be resolved."
        message
      end

      # Extract class from dependency hash
      # @param dep [Hash] Dependency information
      # @return [Class] The dependency class
      def extract_class(dep)
        klass = dep[:klass]
        klass.is_a?(Reference) ? klass.deref : klass
      end
    end
  end
end
