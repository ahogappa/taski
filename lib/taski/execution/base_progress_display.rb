# frozen_string_literal: true

require "monitor"

module Taski
  module Execution
    # Base class for progress display implementations.
    # Provides common task tracking and lifecycle management.
    # Subclasses override template methods for custom rendering.
    class BaseProgressDisplay
      # Shared task progress tracking
      class TaskProgress
        # Run lifecycle tracking
        attr_accessor :run_state, :run_start_time, :run_end_time, :run_error, :run_duration
        # Clean lifecycle tracking
        attr_accessor :clean_state, :clean_start_time, :clean_end_time, :clean_error, :clean_duration
        # Display properties
        attr_accessor :is_impl_candidate
        # Group tracking
        attr_accessor :groups, :current_group_index

        def initialize
          # Run lifecycle
          @run_state = :pending
          @run_start_time = nil
          @run_end_time = nil
          @run_error = nil
          @run_duration = nil
          # Clean lifecycle
          @clean_state = nil # nil means clean hasn't started
          @clean_start_time = nil
          @clean_end_time = nil
          @clean_error = nil
          @clean_duration = nil
          # Display
          @is_impl_candidate = false
          # Groups
          @groups = []
          @current_group_index = nil
        end

        # Returns the most relevant state for display
        def state
          @clean_state || @run_state
        end

        # Legacy accessors for backward compatibility
        def start_time
          @clean_start_time || @run_start_time
        end

        def end_time
          @clean_end_time || @run_end_time
        end

        def error
          @clean_error || @run_error
        end

        def duration
          @clean_duration || @run_duration
        end
      end

      # Tracks the progress of a group within a task
      class GroupProgress
        attr_accessor :name, :state, :start_time, :end_time, :duration, :error, :last_message

        def initialize(name)
          @name = name
          @state = :pending
          @start_time = nil
          @end_time = nil
          @duration = nil
          @error = nil
          @last_message = nil
        end
      end

      def initialize(output: $stdout)
        @output = output
        @tasks = {}
        @monitor = Monitor.new
        @nest_level = 0
        @root_task_class = nil
        @output_capture = nil
        @start_time = nil
        @message_queue = []
      end

      # Set the output capture for getting task output
      # @param capture [ThreadOutputCapture] The output capture instance
      def set_output_capture(capture)
        @monitor.synchronize do
          @output_capture = capture
        end
      end

      # Set the root task to build tree structure
      # Only sets root task if not already set (prevents nested executor overwrite)
      # @param root_task_class [Class] The root task class
      def set_root_task(root_task_class)
        @monitor.synchronize do
          return if @root_task_class # Don't overwrite existing root task
          @root_task_class = root_task_class
          on_root_task_set
        end
      end

      # Register which impl was selected for a section
      # @param section_class [Class] The section class
      # @param impl_class [Class] The selected implementation class
      def register_section_impl(section_class, impl_class)
        @monitor.synchronize do
          on_section_impl_registered(section_class, impl_class)
        end
      end

      # @param task_class [Class] The task class to register
      def register_task(task_class)
        @monitor.synchronize do
          return if @tasks.key?(task_class)
          @tasks[task_class] = TaskProgress.new
          on_task_registered(task_class)
        end
      end

      # @param task_class [Class] The task class to check
      # @return [Boolean] true if the task is registered
      def task_registered?(task_class)
        @monitor.synchronize do
          @tasks.key?(task_class)
        end
      end

      # @param task_class [Class] The task class to update
      # @param state [Symbol] The new state
      # @param duration [Float] Duration in milliseconds (for completed tasks)
      # @param error [Exception] Error object (for failed tasks)
      def update_task(task_class, state:, duration: nil, error: nil)
        @monitor.synchronize do
          progress = @tasks[task_class]
          # Register task if not already registered (for late-registered tasks)
          progress ||= @tasks[task_class] = TaskProgress.new

          apply_state_transition(progress, state, duration, error)
          on_task_updated(task_class, state, duration, error)
        end
      end

      # @param task_class [Class] The task class
      # @return [Symbol] The task state
      def task_state(task_class)
        @monitor.synchronize do
          @tasks[task_class]&.state
        end
      end

      # Update group state for a task.
      # @param task_class [Class] The task class containing the group
      # @param group_name [String] The name of the group
      # @param state [Symbol] The new state (:running, :completed, :failed)
      # @param duration [Float, nil] Duration in milliseconds (for completed groups)
      # @param error [Exception, nil] Error object (for failed groups)
      def update_group(task_class, group_name, state:, duration: nil, error: nil)
        @monitor.synchronize do
          progress = @tasks[task_class]
          return unless progress

          apply_group_state_transition(progress, group_name, state, duration, error)
          on_group_updated(task_class, group_name, state, duration, error)
        end
      end

      def start
        should_start = false
        @monitor.synchronize do
          @nest_level += 1
          return if @nest_level > 1 # Already running from outer executor
          return unless should_activate?

          @start_time = Time.now
          should_start = true
        end

        return unless should_start

        on_start
      end

      def stop
        should_stop = false
        @monitor.synchronize do
          @nest_level -= 1 if @nest_level > 0
          return unless @nest_level == 0

          should_stop = true
        end

        return unless should_stop

        on_stop
        flush_queued_messages
      end

      # Queue a message to be displayed after progress display stops.
      # Thread-safe for concurrent task execution.
      # @param text [String] The message text to queue
      def queue_message(text)
        @monitor.synchronize { @message_queue << text }
      end

      protected

      # Template methods - override in subclasses

      # Called when root task is set. Override to build tree structure.
      def on_root_task_set
        # Default: no-op
      end

      # Called when a section impl is registered.
      def on_section_impl_registered(section_class, impl_class)
        # Default: no-op
      end

      # Called when a task is registered.
      def on_task_registered(task_class)
        # Default: no-op
      end

      # Called when a task state is updated.
      def on_task_updated(task_class, state, duration, error)
        # Default: no-op
      end

      # Called when a group state is updated.
      def on_group_updated(task_class, group_name, state, duration, error)
        # Default: no-op
      end

      # Called to determine if display should activate.
      # @return [Boolean] true if display should start
      def should_activate?
        true
      end

      # Called when display starts.
      def on_start
        # Default: no-op
      end

      # Called when display stops.
      def on_stop
        # Default: no-op
      end

      # Shared tree traversal for subclasses

      # Register all tasks from a tree structure recursively
      def register_tasks_from_tree(node)
        return unless node

        task_class = node[:task_class]
        @tasks[task_class] ||= TaskProgress.new
        @tasks[task_class].is_impl_candidate = true if node[:is_impl_candidate]

        node[:children].each { |child| register_tasks_from_tree(child) }
      end

      # Utility methods for subclasses

      # Get short name of a task class
      def short_name(task_class)
        return "Unknown" unless task_class
        task_class.name&.split("::")&.last || task_class.to_s
      end

      # Format duration for display
      def format_duration(ms)
        if ms >= 1000
          "#{(ms / 1000.0).round(1)}s"
        else
          "#{ms.round(1)}ms"
        end
      end

      # Check if output is a TTY
      def tty?
        @output.tty?
      end

      # Collect all dependencies of a task class recursively
      # Useful for determining which tasks are needed by a selected implementation
      # @param task_class [Class] The task class to collect dependencies for
      # @return [Set<Class>] Set of all dependency task classes (including the task itself)
      def collect_all_dependencies(task_class)
        deps = Set.new
        collect_dependencies_recursive(task_class, deps)
        deps
      end

      private

      # Recursively collect dependencies into the given set
      # @param task_class [Class] The task class
      # @param collected [Set<Class>] Accumulated dependencies
      def collect_dependencies_recursive(task_class, collected)
        return if collected.include?(task_class)
        collected.add(task_class)

        task_class.cached_dependencies.each do |dep|
          collect_dependencies_recursive(dep, collected)
        end
      end

      # Flush all queued messages to output.
      # Called when progress display stops.
      def flush_queued_messages
        messages = @monitor.synchronize { @message_queue.dup.tap { @message_queue.clear } }
        messages.each { |msg| @output.puts(msg) }
      end

      # Apply state transition to TaskProgress
      # Note: Once a task reaches :completed or :failed, it cannot go back to :running.
      # This prevents progress count from decreasing when nested executors re-execute tasks.
      def apply_state_transition(progress, state, duration, error)
        case state
        # Run lifecycle states
        when :pending
          progress.run_state = :pending
        when :running
          # Don't transition back to running if already completed or failed
          return if progress.run_state == :completed || progress.run_state == :failed
          progress.run_state = :running
          progress.run_start_time = Time.now
        when :completed
          progress.run_state = :completed
          progress.run_end_time = Time.now
          progress.run_duration = duration if duration
        when :failed
          progress.run_state = :failed
          progress.run_end_time = Time.now
          progress.run_error = error if error
        # Clean lifecycle states
        when :cleaning
          progress.clean_state = :cleaning
          progress.clean_start_time = Time.now
        when :clean_completed
          progress.clean_state = :clean_completed
          progress.clean_end_time = Time.now
          progress.clean_duration = duration if duration
        when :clean_failed
          progress.clean_state = :clean_failed
          progress.clean_end_time = Time.now
          progress.clean_error = error if error
        end
      end

      # Apply state transition to GroupProgress
      def apply_group_state_transition(progress, group_name, state, duration, error)
        case state
        when :running
          group = GroupProgress.new(group_name)
          group.state = :running
          group.start_time = Time.now
          progress.groups << group
          progress.current_group_index = progress.groups.size - 1
        when :completed
          group = progress.groups.find { |g| g.name == group_name && g.state == :running }
          if group
            group.state = :completed
            group.end_time = Time.now
            group.duration = duration
          end
          progress.current_group_index = nil
        when :failed
          group = progress.groups.find { |g| g.name == group_name && g.state == :running }
          if group
            group.state = :failed
            group.end_time = Time.now
            group.duration = duration
            group.error = error
          end
          progress.current_group_index = nil
        end
      end
    end
  end
end
