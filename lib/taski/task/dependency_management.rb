# frozen_string_literal: true

module Taski
  class Task
    # Module for managing task dependencies and resolution
    module DependencyManagement
      # Resolve dependencies for this task
      def resolve(queue, resolved)
        resolve_common(queue, resolved) { create_defined_methods }
      end

      # Hook called when build/clean methods are defined
      # This triggers static analysis of dependencies
      def method_added(method_name)
        super
        return unless CoreConstants::ANALYZED_METHODS.include?(method_name)
        # Call dependency analysis (overridden by dependency_resolver module)
        analyze_dependencies_at_definition
      end

      # Create a reference to a task class (can be used anywhere)
      # @param klass [String] The class name to reference
      # @return [Reference, Class] A reference object or actual class
      def ref(klass_name)
        # During dependency analysis, track as dependency but defer resolution
        if Thread.current[CoreConstants::TASKI_ANALYZING_DEFINE_KEY]
          # Create Reference object for deferred resolution
          reference = Reference.new(klass_name)
          # Track as dependency by throwing unresolved
          throw :unresolved, [reference, :deref]
        else
          # At runtime, try to resolve to actual class for convenience
          # This provides better ergonomics for define API usage
          begin
            Object.const_get(klass_name)
          rescue NameError
            # Fall back to Reference object if class doesn't exist yet
            # This maintains compatibility with forward references
            Reference.new(klass_name)
          end
        end
      end

      # Get or create resolution state for define API
      # @return [Hash] Resolution state hash
      def resolution_state
        @__resolution_state ||= {}
      end

      # Reset resolution state for define API analysis
      # @return [void]
      def reset_resolution_state
        @__resolution_state = {}
      end

      # Register rescue handler for dependency errors
      # @param exception_classes [Array<Class>] Exception classes to handle
      # @param handler [Proc] Lambda to handle exceptions
      def rescue_deps(*exception_classes, handler)
        @rescue_handlers ||= []
        exception_classes.each do |exception_class|
          @rescue_handlers << [exception_class, handler]
        end
      end

      # Find rescue handler for a given exception
      # @param exception [Exception] Exception to find handler for
      # @return [Array, nil] Handler pair [exception_class, handler] or nil
      def find_dependency_rescue_handler(exception)
        return nil unless @rescue_handlers
        @rescue_handlers.find { |exception_class, handler| exception.is_a?(exception_class) }
      end

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
        previous_parent = Thread.current[CoreConstants::TASKI_CURRENT_PARENT_TASK_KEY]
        Thread.current[CoreConstants::TASKI_CURRENT_PARENT_TASK_KEY] = self
        begin
          yield
        ensure
          Thread.current[CoreConstants::TASKI_CURRENT_PARENT_TASK_KEY] = previous_parent
        end
      end

      # Get the current task instance (may be nil)
      # @return [Task, nil] Current task instance or nil if not built
      def current_instance
        @__task_instance
      end

      # Get the current task instance or create a new one for cleaning
      # @return [Task] Task instance for cleaning operations
      def instance_for_cleanup
        @__task_instance || new
      end
    end
  end
end
