# frozen_string_literal: true

require 'monitor'

module Taski
  class Task
    class << self
      # === Lifecycle Management ===

      # Build this task and all its dependencies
      def build
        resolve_dependencies.reverse.each do |task_class|
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
            raise CircularDependencyError, "Circular dependency detected: #{self.name} is already being built"
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
        "#{self.name}#{THREAD_KEY_SUFFIX}"
      end

      # Build and configure task instance
      # @return [Task] Built task instance
      def build_instance
        instance = self.new
        begin
          instance.build
          instance
        rescue => e
          # Log the error but don't let it crash the entire system
          warn "Taski: Failed to build #{self.name}: #{e.message}"
          warn "Taski: #{e.backtrace.first}" if e.backtrace
          raise TaskBuildError, "Failed to build task #{self.name}: #{e.message}"
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