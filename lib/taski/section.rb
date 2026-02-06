# frozen_string_literal: true

require_relative "task"

module Taski
  class Section < Task
    class << self
      # @param interface_methods [Array<Symbol>] Names of interface methods
      def interfaces(*interface_methods)
        exports(*interface_methods)
      end

      # Section does not have static dependencies for execution.
      # The impl method is called at runtime to determine the actual implementation.
      # Static dependencies (impl candidates) are only used for tree display and circular detection.
      def cached_dependencies
        Set.new
      end
    end

    def run
      implementation_class = impl
      unless implementation_class
        # Clear exported values to prevent stale data from leaking
        self.class.exported_methods.each { |method| instance_variable_set("@#{method}", nil) }
        return
      end

      # Register runtime dependency for clean phase
      register_runtime_dependency(implementation_class)

      # Notify unselected nested impl candidates as skipped
      notify_unselected_candidates_skipped(implementation_class)

      apply_interface_to_implementation(implementation_class)

      self.class.exported_methods.each do |method|
        value = implementation_class.public_send(method)
        instance_variable_set("@#{method}", value)
      end
    end

    # @return [Class] The implementation task class
    # @raise [NotImplementedError] If not implemented by subclass
    def impl
      raise NotImplementedError, "Subclasses must implement the impl method to return implementation class"
    end

    private

    # Register the selected implementation as a runtime dependency.
    # This allows the clean phase to include the dynamically selected impl.
    # Handles nil ExecutionFacade gracefully.
    #
    # @param impl_class [Class] The selected implementation class
    def register_runtime_dependency(impl_class)
      context = Execution::ExecutionFacade.current
      context&.register_runtime_dependency(self.class, impl_class)
    end

    # Notify observers that unselected nested impl candidates are skipped.
    # Only nested classes (impl candidates) are notified, not external implementations.
    #
    # @param selected_impl [Class] The selected implementation class
    def notify_unselected_candidates_skipped(selected_impl)
      context = Execution::ExecutionFacade.current
      return unless context

      timestamp = Time.now
      nested_impl_candidates.each do |candidate|
        next if candidate == selected_impl

        context.notify_task_updated(
          candidate,
          previous_state: :pending,
          current_state: :skipped,
          timestamp: timestamp
        )
      end
    end

    # Find nested classes that are impl candidates for this Section.
    # A nested impl candidate is a constant defined directly in this Section class
    # that is itself a subclass of Taski::Task.
    #
    # @return [Array<Class>] Nested impl candidate classes
    def nested_impl_candidates
      self.class.constants
        .map { |c| self.class.const_get(c) }
        .select { |c| c.is_a?(Class) && c < Taski::Task }
    end

    # @param implementation_class [Class] The implementation task class
    def apply_interface_to_implementation(implementation_class)
      interface_methods = self.class.exported_methods
      return if interface_methods.empty?

      implementation_class.exports(*interface_methods)
    end
  end
end
