# frozen_string_literal: true

module Taski
  module Execution
    # Base class for observers of the execution lifecycle.
    # Subclasses override only the events they care about.
    #
    # All events are defined as no-op methods. The +context+ accessor
    # is auto-injected by ExecutionFacade#add_observer.
    #
    # == Event Methods
    #
    # - on_ready — facade is configured, observer can pull from context
    # - on_start — execution is about to begin
    # - on_stop — execution has finished
    # - on_task_updated(task_class, previous_state:, current_state:, phase:, timestamp:)
    # - on_group_started(task_class, group_name, phase:, timestamp:)
    # - on_group_completed(task_class, group_name, phase:, timestamp:)
    class TaskObserver
      attr_accessor :context

      def on_ready
      end

      def on_start
      end

      def on_stop
      end

      def on_task_updated(task_class, previous_state:, current_state:, phase:, timestamp:)
      end

      def on_group_started(task_class, group_name, phase:, timestamp:)
      end

      def on_group_completed(task_class, group_name, phase:, timestamp:)
      end
    end
  end
end
