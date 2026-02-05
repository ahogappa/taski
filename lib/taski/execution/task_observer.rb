# frozen_string_literal: true

module Taski
  module Execution
    # Base class for task execution observers.
    # Observers receive notifications about task lifecycle events and can
    # pull additional information from the context.
    #
    # == Observer Pattern with Pull API
    #
    # Observers receive event notifications (Push) with minimal data,
    # and can pull additional context information as needed:
    #
    #   - Push: task_class, previous_state, current_state, timestamp
    #   - Pull: context.current_phase, context.dependency_graph, context.output_stream
    #
    # == Usage
    #
    # Subclass TaskObserver and override the methods you need:
    #
    #   class MyObserver < Taski::Execution::TaskObserver
    #     def on_ready
    #       @graph = context.dependency_graph
    #       build_tree(@graph)
    #     end
    #
    #     def on_task_updated(task_class, previous_state:, current_state:, timestamp:)
    #       case [previous_state, current_state]
    #       when [:pending, :running]
    #         record_start(task_class, timestamp)
    #       when [:running, :completed]
    #         record_completion(task_class, timestamp)
    #       end
    #     end
    #   end
    #
    # == Registration
    #
    # When added to ExecutionContext, the context is automatically injected:
    #
    #   context.add_observer(my_observer)
    #   # my_observer.context is now set to context
    #
    class TaskObserver
      # The execution context that this observer is attached to.
      # Set automatically when added via ExecutionContext#add_observer.
      # @return [ExecutionContext, nil]
      attr_accessor :context

      # Called when execution is ready (root task and dependencies resolved).
      # Use this to pull initial state from context.
      def on_ready
      end

      # Called when execution starts.
      def on_start
      end

      # Called when execution stops.
      def on_stop
      end

      # Called when a phase starts.
      # @param phase [Symbol] :run or :clean
      def on_phase_started(phase)
      end

      # Called when a phase completes.
      # @param phase [Symbol] :run or :clean
      def on_phase_completed(phase)
      end

      # Called when a task's state changes.
      # @param task_class [Class] The task class
      # @param previous_state [Symbol] The previous state
      # @param current_state [Symbol] The new state
      # @param timestamp [Time] When the transition occurred
      # @param error [Exception, nil] The error if state is :failed
      def on_task_updated(task_class, previous_state:, current_state:, timestamp:, error: nil)
      end

      # Called when a group starts.
      # @param task_class [Class] The task class containing the group
      # @param group_name [String] The group name
      def on_group_started(task_class, group_name)
      end

      # Called when a group completes.
      # @param task_class [Class] The task class containing the group
      # @param group_name [String] The group name
      def on_group_completed(task_class, group_name)
      end
    end
  end
end
