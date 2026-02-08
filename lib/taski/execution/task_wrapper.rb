# frozen_string_literal: true

require "monitor"

module Taski
  module Execution
    # Manages state and synchronization for a single task instance.
    # Does NOT start threads or fibers — Executor and WorkerPool control scheduling.
    #
    # State transitions (both run and clean phases):
    #   pending -> running -> completed | failed
    #   pending -> skipped (run-phase only)
    class TaskWrapper
      attr_reader :task, :result, :error, :clean_error

      STATE_PENDING = :pending
      STATE_RUNNING = :running
      STATE_COMPLETED = :completed
      STATE_FAILED = :failed
      STATE_SKIPPED = :skipped

      def initialize(task, registry:, execution_facade: nil, args: nil)
        @task = task
        @registry = registry
        @execution_facade = execution_facade
        @args = args
        @result = nil
        @clean_result = nil
        @error = nil
        @clean_error = nil
        @monitor = Monitor.new
        @condition = @monitor.new_cond
        @clean_condition = @monitor.new_cond
        @state = STATE_PENDING
        @clean_state = STATE_PENDING
        @waiters = []
      end

      def state
        @monitor.synchronize { @state }
      end

      def pending? = state == STATE_PENDING
      def completed? = state == STATE_COMPLETED
      def failed? = state == STATE_FAILED
      def skipped? = state == STATE_SKIPPED

      def reset!
        @monitor.synchronize do
          @state = STATE_PENDING
          @clean_state = STATE_PENDING
          @result = nil
          @clean_result = nil
          @error = nil
          @clean_error = nil
        end
        @task.reset! if @task.respond_to?(:reset!)
        @registry.reset!
      end

      def run
        with_args_lifecycle do
          trigger_execution_and_wait
          raise @error if @error # steep:ignore
          @result
        end
      end

      def clean
        with_args_lifecycle do
          trigger_clean_and_wait
          @clean_result
        end
      end

      # Runs execution followed by cleanup. Block is called between phases.
      def run_and_clean(&block)
        facade = ensure_facade
        facade.notify_start # Pre-increment nest_level to prevent double rendering
        result = run
        block&.call
        result
      ensure
        clean
        facade&.notify_stop # Final decrement and render
      end

      def get_exported_value(method_name)
        with_args_lifecycle do
          trigger_execution_and_wait
          raise @error if @error # steep:ignore
          @task.public_send(method_name)
        end
      end

      # Atomically resolve the dependency value for a waiting Fiber.
      # Returns a status tuple indicating how the caller should proceed:
      # - [:completed, value] → dependency already done, resume immediately
      # - [:failed, error]   → dependency failed, propagate error
      # - [:wait]            → dependency running, Fiber parked (will be resumed via thread_queue)
      # - [:start]           → dependency was PENDING, now RUNNING (caller must drive it)
      def request_value(method, thread_queue, fiber)
        @monitor.synchronize do
          case @state
          when STATE_COMPLETED
            value = @task.public_send(method)
            [:completed, value]
          when STATE_FAILED
            [:failed, @error]
          when STATE_RUNNING
            @waiters << [thread_queue, fiber, method]
            [:wait]
          else
            # PENDING → atomically transition to RUNNING
            @state = STATE_RUNNING
            @waiters << [thread_queue, fiber, method]
            [:start]
          end
        end
      end

      def mark_running
        @monitor.synchronize do
          return false unless @state == STATE_PENDING
          @state = STATE_RUNNING
          true
        end
      end

      def mark_completed(result)
        waiters_to_notify = nil
        @monitor.synchronize do
          @result = result
          @state = STATE_COMPLETED
          @condition.broadcast
          waiters_to_notify = @waiters.dup
          @waiters.clear
        end
        notify_fiber_waiters_completed(waiters_to_notify)
        update_progress(:completed)
      end

      def mark_failed(error)
        waiters_to_notify = nil
        @monitor.synchronize do
          @error = error
          @state = STATE_FAILED
          @condition.broadcast
          waiters_to_notify = @waiters.dup
          @waiters.clear
        end
        notify_fiber_waiters_failed(waiters_to_notify, error)
        update_progress(:failed)
      end

      def mark_skipped
        @monitor.synchronize do
          return false unless @state == STATE_PENDING
          @state = STATE_SKIPPED
          @condition.broadcast
        end
        notify_skipped
        true
      end

      def mark_clean_running
        @monitor.synchronize do
          return false unless @clean_state == STATE_PENDING
          @clean_state = STATE_RUNNING
          true
        end
      end

      def mark_clean_completed(result)
        @monitor.synchronize do
          @clean_result = result
          @clean_state = STATE_COMPLETED
          @clean_condition.broadcast
        end
        update_clean_progress(:completed)
      end

      def mark_clean_failed(error)
        @monitor.synchronize do
          @clean_error = error
          @clean_state = STATE_FAILED
          @clean_condition.broadcast
        end
        update_clean_progress(:failed)
      end

      def wait_for_completion
        @monitor.synchronize do
          @condition.wait_until { @state == STATE_COMPLETED || @state == STATE_FAILED || @state == STATE_SKIPPED }
        end
      end

      def wait_for_clean_completion
        @monitor.synchronize do
          @clean_condition.wait_until { @clean_state == STATE_COMPLETED || @clean_state == STATE_FAILED }
        end
      end

      def method_missing(method_name, *args, &block)
        if @task.class.exported_methods.include?(method_name)
          get_exported_value(method_name)
        else
          super
        end
      end

      def respond_to_missing?(method_name, include_private = false)
        @task.class.exported_methods.include?(method_name) || super
      end

      private

      def with_args_lifecycle(&block)
        # If args are already set, just execute the block
        return yield if Taski.args

        options = @args || {}
        Taski.send(:with_env, root_task: @task.class) do
          Taski.send(:with_args, options: options, &block)
        end
      end

      def trigger_execution_and_wait
        trigger_and_wait(state_accessor: -> { @state }, condition: @condition) do |facade|
          facade.trigger_execution(@task.class, registry: @registry)
        end
      end

      def trigger_clean_and_wait
        trigger_and_wait(state_accessor: -> { @clean_state }, condition: @clean_condition) do |facade|
          facade.trigger_clean(@task.class, registry: @registry)
        end
      end

      def trigger_and_wait(state_accessor:, condition:)
        should_execute = false
        @monitor.synchronize do
          case state_accessor.call
          when STATE_PENDING
            check_abort!
            should_execute = true
          when STATE_RUNNING
            condition.wait_until { [STATE_COMPLETED, STATE_FAILED, STATE_SKIPPED].include?(state_accessor.call) }
          when STATE_COMPLETED, STATE_FAILED, STATE_SKIPPED
            # Already done
          end
        end

        yield ensure_facade if should_execute
      end

      def check_abort!
        if @registry.abort_requested?
          raise Taski::TaskAbortException, "Execution aborted - no new tasks will start"
        end
      end

      def ensure_facade
        @execution_facade ||= create_shared_facade
      end

      def create_shared_facade
        ExecutionFacade.build_default(root_task_class: @task.class)
      end

      def notify_skipped
        notify_state_change(previous_state: :pending, current_state: :skipped, phase: :run)
      end

      def update_progress(state)
        notify_state_change(previous_state: :running, current_state: state, phase: :run)
      end

      def update_clean_progress(state)
        notify_state_change(previous_state: :running, current_state: state, phase: :clean)
      end

      def notify_state_change(previous_state:, current_state:, phase:)
        @execution_facade.notify_task_updated(
          @task.class,
          previous_state: previous_state,
          current_state: current_state,
          phase: phase,
          timestamp: Time.now
        )
      end

      def notify_fiber_waiters_completed(waiters)
        waiters.each do |thread_queue, fiber, method|
          value = @task.public_send(method)
          thread_queue.push([:resume, fiber, value])
        end
      end

      def notify_fiber_waiters_failed(waiters, error)
        waiters.each do |thread_queue, fiber, _method|
          thread_queue.push([:resume_error, fiber, error])
        end
      end
    end
  end
end
