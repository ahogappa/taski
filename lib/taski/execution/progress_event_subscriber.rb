# frozen_string_literal: true

module Taski
  module Execution
    # ProgressEventSubscriber provides a simple callback-based API for
    # receiving progress events from task execution.
    #
    # This is ideal for lightweight use cases like logging, notifications,
    # or webhook integrations where you don't need full display control.
    #
    # @example Simple logging
    #   logger = Taski::Execution::ProgressEventSubscriber.new do |events|
    #     events.on_task_start { |task, _| puts "[START] #{task.name}" }
    #     events.on_task_complete { |task, info| puts "[DONE] #{task.name} (#{info[:duration]}ms)" }
    #     events.on_task_fail { |task, info| puts "[FAIL] #{task.name}: #{info[:error]}" }
    #   end
    #
    # @example Webhook notifications
    #   notifier = Taski::Execution::ProgressEventSubscriber.new do |events|
    #     events.on_task_fail do |task, info|
    #       HTTParty.post("https://slack.webhook/...",
    #         body: { text: "Task failed: #{task.name}" }.to_json)
    #     end
    #   end
    #
    # @example Progress tracking
    #   tracker = Taski::Execution::ProgressEventSubscriber.new do |events|
    #     events.on_progress do |summary|
    #       percent = (summary[:completed].to_f / summary[:total] * 100).round(1)
    #       puts "Progress: #{percent}%"
    #     end
    #   end
    class ProgressEventSubscriber
      attr_reader :root_task_class, :output_capture

      def initialize(&block)
        @handlers = Hash.new { |h, k| h[k] = [] }
        @tasks = {}
        @root_task_class = nil
        @output_capture = nil
        block&.call(self)
      end

      # ========================================
      # Callback Registration Methods
      # ========================================

      # Register a callback for execution start.
      # @yield Called when execution starts
      def on_execution_start(&block)
        @handlers[:execution_start] << block
      end

      # Register a callback for execution stop.
      # @yield Called when execution stops
      def on_execution_stop(&block)
        @handlers[:execution_stop] << block
      end

      # Register a callback for task start.
      # @yield [task_class, info] Called when a task starts running
      def on_task_start(&block)
        @handlers[:task_start] << block
      end

      # Register a callback for task completion.
      # @yield [task_class, info] Called when a task completes successfully
      def on_task_complete(&block)
        @handlers[:task_complete] << block
      end

      # Register a callback for task failure.
      # @yield [task_class, info] Called when a task fails
      def on_task_fail(&block)
        @handlers[:task_fail] << block
      end

      # Register a callback for task skip.
      # @yield [task_class, info] Called when a task is skipped
      def on_task_skip(&block)
        @handlers[:task_skip] << block
      end

      # Register a callback for task cleaning start.
      # @yield [task_class, info] Called when a task starts cleaning
      def on_task_cleaning(&block)
        @handlers[:task_cleaning] << block
      end

      # Register a callback for task clean completion.
      # @yield [task_class, info] Called when a task completes cleaning
      def on_task_clean_complete(&block)
        @handlers[:task_clean_complete] << block
      end

      # Register a callback for task clean failure.
      # @yield [task_class, info] Called when a task fails during cleaning
      def on_task_clean_fail(&block)
        @handlers[:task_clean_fail] << block
      end

      # Register a callback for group start.
      # @yield [task_class, group_name] Called when a group starts
      def on_group_start(&block)
        @handlers[:group_start] << block
      end

      # Register a callback for group completion.
      # @yield [task_class, group_name, info] Called when a group completes
      def on_group_complete(&block)
        @handlers[:group_complete] << block
      end

      # Register a callback for progress updates.
      # @yield [summary] Called with progress summary hash
      def on_progress(&block)
        @handlers[:progress] << block
      end

      # ========================================
      # Observer Protocol Methods
      # (Called by ExecutionContext)
      # ========================================

      # Called when execution starts.
      def start
        call_handlers(:execution_start)
      end

      # Called when execution stops.
      def stop
        call_handlers(:execution_stop)
      end

      # Set the root task class.
      # @param root_task_class [Class] The root task class
      def set_root_task(root_task_class)
        @root_task_class = root_task_class
      end

      # Set the output capture for getting task output.
      # @param capture [ThreadOutputCapture] The output capture instance
      def set_output_capture(capture)
        @output_capture = capture
      end

      # Register a section implementation.
      # @param section_class [Class] The section class
      # @param impl_class [Class] The selected implementation class
      def register_section_impl(section_class, impl_class)
        # Store for potential future use
        @tasks[impl_class] ||= {state: :pending}
      end

      # Register a task for tracking.
      # @param task_class [Class] The task class to register
      def register_task(task_class)
        return if @tasks.key?(task_class)
        @tasks[task_class] = {state: :pending}
      end

      # Update task state and trigger appropriate callbacks.
      # @param task_class [Class] The task class
      # @param state [Symbol] The new state
      # @param duration [Float, nil] Duration in milliseconds
      # @param error [Exception, nil] Error object
      def update_task(task_class, state:, duration: nil, error: nil)
        @tasks[task_class] ||= {state: :pending}
        @tasks[task_class][:state] = state
        @tasks[task_class][:duration] = duration if duration
        @tasks[task_class][:error] = error if error

        info = {duration: duration, error: error}

        case state
        when :running
          call_handlers(:task_start, task_class, info)
        when :completed
          call_handlers(:task_complete, task_class, info)
        when :failed
          call_handlers(:task_fail, task_class, info)
        when :skipped
          call_handlers(:task_skip, task_class, info)
        when :cleaning
          call_handlers(:task_cleaning, task_class, info)
        when :clean_completed
          call_handlers(:task_clean_complete, task_class, info)
        when :clean_failed
          call_handlers(:task_clean_fail, task_class, info)
        end

        emit_progress
      end

      # Update group state and trigger appropriate callbacks.
      # @param task_class [Class] The task class containing the group
      # @param group_name [String] The name of the group
      # @param state [Symbol] The new state
      # @param duration [Float, nil] Duration in milliseconds
      # @param error [Exception, nil] Error object
      def update_group(task_class, group_name, state:, duration: nil, error: nil)
        info = {duration: duration, error: error}

        case state
        when :running
          call_handlers(:group_start, task_class, group_name)
        when :completed, :failed
          call_handlers(:group_complete, task_class, group_name, info)
        end
      end

      private

      def call_handlers(event, *args)
        @handlers[event].each { |handler| handler.call(*args) }
      end

      def emit_progress
        return if @handlers[:progress].empty?

        summary = {
          completed: @tasks.values.count { |t| t[:state] == :completed },
          total: @tasks.size,
          running: @tasks.select { |_, t| t[:state] == :running }.keys,
          failed: @tasks.select { |_, t| t[:state] == :failed }.keys
        }

        call_handlers(:progress, summary)
      end
    end
  end
end
