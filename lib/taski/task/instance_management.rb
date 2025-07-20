# frozen_string_literal: true

module Taski
  class Task
    # Module for instance and lifecycle management
    module InstanceManagement
      # Run this task and all its dependencies
      # @param args [Hash] Optional arguments for parametrized runs
      # @return [Task] Returns task instance (singleton or temporary)
      def run(**args)
        if args.empty?
          resolve_dependencies.reverse_each do |task_class|
            execute_with_parent_context(task_class) { task_class.ensure_instance_built }
          end
          ensure_instance_built
          # Return the singleton instance for consistency
          current_instance
        else
          run_with_args(args)
        end
      end

      # Clean this task and all its dependencies in reverse order
      def clean
        resolve_dependencies.each do |task_class|
          instance = task_class.instance_for_cleanup
          instance.clean
        end
      end

      # Reset task instance and cached data to prevent memory leaks
      # @return [self] Returns self for method chaining
      def reset!
        @__task_instance = nil
        @__defined_values = nil
        @__defined_for_resolve = nil
        @__parametrized_cache = nil
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
        if @__parametrized_cache && @__parametrized_cache[:args] == args
          return @__parametrized_cache[:instance]
        end

        @__parametrized_cache = nil

        resolve_dependencies.reverse_each do |task_class|
          next if task_class == self
          task_class.ensure_instance_built
        end

        temp_instance = new(args)

        result = InstanceBuilder.with_build_logging(name.to_s,
          dependencies: @dependencies || [],
          args: args) do
          temp_instance.run
          temp_instance
        end

        @__parametrized_cache = {
          args: args,
          instance: result
        }
        result
      end

      # Keep old method name for compatibility
      alias_method :build_with_args, :run_with_args
      private :run_with_args, :build_with_args

      # === Instance Management ===

      # Ensure task instance is built (public because called from build)
      # @return [Task] The built task instance
      def ensure_instance_built
        return @__task_instance if @__task_instance

        check_circular_dependency
        create_and_build_instance
        @__task_instance
      end

      private

      # === Instance Management Helper Methods ===

      # Check for circular dependencies using call stack tracking
      # @raise [CircularDependencyError] If circular dependency is detected
      def check_circular_dependency
        # Get the current call stack for this build process
        context = ExecutionContext.current

        if context.building?(self)
          # Build detailed error message with the actual cycle
          current_stack = context.build_stack
          cycle_start_index = current_stack.index(self)
          cycle_path = current_stack[cycle_start_index..] + [self]

          path_names = cycle_path.map { |klass| klass.name || klass.to_s }
          message = "Circular dependency detected!\n"
          message += "Cycle: #{path_names.join(" → ")}\n\n"
          message += "The runtime chain is:\n"

          cycle_path.each_cons(2).with_index do |(from, to), index|
            message += "  #{index + 1}. #{from.name} is trying to build → #{to.name}\n"
          end

          message += "\nThis creates an infinite loop that cannot be resolved."
          raise CircularDependencyError, message
        end
      end

      # Create and build instance with call stack tracking
      # @return [void] Sets @__task_instance
      def create_and_build_instance
        context = ExecutionContext.current
        context.push_build(self)
        begin
          build_dependencies
          @__task_instance = build_instance
        ensure
          context.pop_build(self)
        end
      end

      # === Core Helper Methods ===

      # Build and configure task instance
      # @return [Task] Built task instance
      def build_instance
        instance = new
        # Get current parent task for rescue_deps handling
        parent_task = ExecutionContext.current.current_parent_task
        InstanceBuilder.with_build_logging(name.to_s,
          dependencies: @dependencies || [],
          parent_task: parent_task) do
          instance.run
          instance
        end
      end
    end
  end
end
