# frozen_string_literal: true

require "monitor"

module Taski
  class Task
    class << self
      # === Lifecycle Management ===

      # Run this task and all its dependencies
      # @param args [Hash] Optional arguments for parametrized runs
      # @return [Task] Returns task instance (singleton or temporary)
      def run(**args)
        if args.empty?
          resolve_dependencies.reverse_each do |task_class|
            execute_with_parent_context(task_class) { task_class.ensure_instance_built }
          end
          # Ensure this task itself is also built after dependencies
          ensure_instance_built
          # Return the singleton instance for consistency
          current_instance
        else
          run_with_args(args)
        end
      end

      # Alias for backward compatibility
      alias_method :build, :run

      # Clean this task and all its dependencies in reverse order
      def clean
        resolve_dependencies.each do |task_class|
          # Get existing instance or create new one for cleaning
          instance = task_class.instance_for_cleanup
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

      # Refresh task state
      # @return [self] Returns self for method chaining
      def refresh
        reset!
      end

      # === Parametrized Run Support ===

      # Run temporary instance with arguments
      # @param args [Hash] Run arguments
      # @return [Task] Temporary task instance
      def run_with_args(args)
        # Resolve dependencies first (same as normal run)
        resolve_dependencies.reverse_each do |task_class|
          task_class.ensure_instance_built
        end

        # Create temporary instance with arguments
        temp_instance = new(args)

        # Run with logging using common utility
        InstanceBuilder.with_build_logging(name.to_s,
          dependencies: @dependencies || [],
          args: args) do
          temp_instance.run
          temp_instance
        end
      end

      # Keep old method name for compatibility
      alias_method :build_with_args, :run_with_args
      private :run_with_args, :build_with_args

      # === Dependency Management ===

      # Build all dependencies of this task
      def build_dependencies
        resolve_dependencies

        (@dependencies || []).each do |dep|
          dep_class = extract_class(dep)
          next if dep_class == self

          build_dependency(dep_class)
        end
      end

      # Build a single dependency task
      # @param dep_class [Class] The dependency class to build (guaranteed to be Task/Section)
      def build_dependency(dep_class)
        execute_with_parent_context(dep_class) { dep_class.ensure_instance_built }
      end

      # Execute block with parent task context for rescue_deps handling
      # @param task_class [Class] Task class being executed
      # @yield Block to execute with parent context
      def execute_with_parent_context(task_class)
        previous_parent = Thread.current[TASKI_CURRENT_PARENT_TASK_KEY]
        Thread.current[TASKI_CURRENT_PARENT_TASK_KEY] = self
        begin
          yield
        ensure
          Thread.current[TASKI_CURRENT_PARENT_TASK_KEY] = previous_parent
        end
      end

      # === Instance Management ===

      # Ensure task instance is built (public because called from build)
      # @return [Task] The built task instance
      def ensure_instance_built
        # Double-checked locking prevents lock contention in multi-threaded builds
        # First check avoids expensive synchronization when instance already exists
        return @__task_instance if @__task_instance

        build_monitor.synchronize do
          return @__task_instance if @__task_instance

          check_circular_dependency
          create_and_build_instance
        end

        @__task_instance
      end

      private

      # === Instance Management Helper Methods ===

      # Check for circular dependencies and raise error if detected
      # @raise [CircularDependencyError] If circular dependency is detected
      def check_circular_dependency
        thread_key = build_thread_key
        if Thread.current[thread_key]
          handle_circular_dependency_detected
        end
      end

      # Handle the case when circular dependency is detected
      # @raise [CircularDependencyError] Always raises with detailed message
      def handle_circular_dependency_detected
        # Build dependency path for better error message
        cycle_path = build_current_dependency_path
        raise CircularDependencyError, build_runtime_circular_dependency_message(cycle_path)
      end

      # Create and build instance with proper thread-local state management
      # @return [void] Sets @__task_instance
      def create_and_build_instance
        thread_key = build_thread_key
        with_build_tracking(thread_key) do
          build_dependencies
          @__task_instance = build_instance
        end
      end

      # Execute block while tracking this task's build state in thread-local storage
      # @param thread_key [String] The thread-local key for this task
      # @yield Block to execute while tracking build state
      def with_build_tracking(thread_key)
        Thread.current[thread_key] = true
        begin
          yield
        ensure
          Thread.current[thread_key] = false
        end
      end

      # === Core Helper Methods ===

      # Get or create build monitor for thread safety
      # @return [Monitor] Thread-safe monitor object
      def build_monitor
        @__build_monitor ||= Monitor.new
      end

      # Generate thread-local key for circular dependency detection
      # Each task uses a unique thread-local key to track if it's currently building
      # @return [String] Thread key for this task's build state
      def build_thread_key
        "#{name}#{THREAD_KEY_SUFFIX}"
      end

      # Build and configure task instance
      # @return [Task] Built task instance
      def build_instance
        instance = new
        # Try to get parent task from calling context
        parent_task = Thread.current[TASKI_CURRENT_PARENT_TASK_KEY]
        InstanceBuilder.with_build_logging(name.to_s,
          dependencies: @dependencies || [], parent_task: parent_task) do
          instance.run
          instance
        end
      end

      # Clear thread-local state for this task
      def clear_thread_local_state
        Thread.current.keys.each do |key|
          Thread.current[key] = nil if key.to_s.include?(build_thread_key)
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
        CircularDependencyDetector.build_error_message(cycle_path, "runtime")
      end
    end
  end
end
