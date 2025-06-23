# frozen_string_literal: true

require "monitor"

module Taski
  class Task
    class << self
      # === Lifecycle Management ===

      # Build this task and all its dependencies
      # @param args [Hash] Optional arguments for parametrized builds
      # @return [Task] Returns task instance (singleton or temporary)
      def build(**args)
        if args.empty?
          # Traditional build: singleton instance with caching
          resolve_dependencies.reverse_each do |task_class|
            task_class.ensure_instance_built
          end
          # Return the singleton instance for consistency
          instance_variable_get(:@__task_instance)
        else
          # Parametrized build: temporary instance without caching
          build_with_args(args)
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

      # === Parametrized Build Support ===

      # Build temporary instance with arguments
      # @param args [Hash] Build arguments
      # @return [Task] Temporary task instance
      def build_with_args(args)
        # Resolve dependencies first (same as normal build)
        resolve_dependencies.reverse_each do |task_class|
          task_class.ensure_instance_built
        end

        # Create temporary instance with arguments
        temp_instance = new
        temp_instance.instance_variable_set(:@build_args, args)

        # Build with logging using common utility
        Utils::TaskBuildHelpers.with_build_logging(name.to_s,
          dependencies: @dependencies || [],
          args: args) do
          temp_instance.build
          temp_instance
        end
      end

      private :build_with_args

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
        Utils::TaskBuildHelpers.with_build_logging(name.to_s,
          dependencies: @dependencies || []) do
          instance.build
          instance
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

      private

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
        Utils::CircularDependencyHelpers.build_error_message(cycle_path, "runtime")
      end

      include Utils::DependencyUtils
      private :extract_class
    end
  end
end
