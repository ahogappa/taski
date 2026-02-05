# frozen_string_literal: true

require 'monitor'
require 'liquid'
require_relative '../theme/default'
require_relative '../../execution/task_observer'
require_relative 'filters'
require_relative 'tags'
require_relative 'theme_drop'

module Taski
  module Progress
    module Layout
      # Base class for layout implementations.
      # Inherits from TaskObserver to receive execution events.
      #
      # Layouts are responsible for:
      # - Receiving events from ExecutionContext (Observer pattern via TaskObserver)
      # - Rendering templates using Liquid
      # - Handling screen output
      #
      # Layout does NOT hold complex state. It tracks only:
      # - Task states (for counting and display)
      # - Start times (for duration calculation)
      #
      # === Event to Template Mapping ===
      #
      # ExecutionContext Event              | Layout Method              | Template Method
      # ------------------------------------|----------------------------|---------------------------
      # notify_ready                        | on_ready                   | (initial setup)
      # notify_start (on_start)             | start                      | (internal setup)
      # notify_stop (on_stop)               | stop                       | execution_complete/fail
      # notify_task_updated                 | on_task_updated            | task_start/success/fail
      # notify_phase_started                | on_phase_started           | (phase tracking)
      # notify_phase_completed              | on_phase_completed         | (phase tracking)
      # notify_group_started                | on_group_started           | group_start
      # notify_group_completed              | on_group_completed         | group_success/fail
      class Base < Taski::Execution::TaskObserver
        attr_reader :spinner_index

        def initialize(output: $stderr, theme: nil)
          @output = output
          @theme = theme || Theme::Default.new
          @theme_drop = ThemeDrop.new(@theme)
          @liquid_environment = build_liquid_environment
          @monitor = Monitor.new

          # Minimal state tracking (for counting and duration calculation)
          # Note: errors are NOT tracked here - they propagate to top level via exceptions (Plan design)
          @task_run_states = {}     # task_class => Symbol (:pending, :running, :completed, :failed, :skipped)
          @task_clean_states = {}   # task_class => Symbol
          @task_start_times = {}    # task_class => {run: Time, clean: Time}
          @task_durations = {}      # task_class => {run: Float, clean: Float}

          @nest_level = 0
          @start_time = nil
          @root_task_class = nil
          @message_queue = []
          @spinner_index = 0
          @spinner_timer = nil
          @spinner_running = false
          @active = false
        end

        # === Observer interface (called by ExecutionContext) ===

        # Set the root task class for tree building
        # Only sets if not already set (prevents nested executor overwrite)
        # @param task_class [Class] The root task class
        def set_root_task(task_class)
          @monitor.synchronize do
            return if @root_task_class

            @root_task_class = task_class
            on_root_task_set
          end
        end

        # Start progress display
        # Increments nest level for nested executor support
        def start
          should_start = false
          @monitor.synchronize do
            @nest_level += 1
            return if @nest_level > 1
            return unless should_activate?

            @start_time = Time.now
            @active = true
            should_start = true
          end

          on_start if should_start
        end

        # Stop progress display
        # Only finalizes when nest level reaches 0 and layout was actually activated
        def stop
          should_stop = false
          was_active = false
          @monitor.synchronize do
            @nest_level -= 1 if @nest_level.positive?
            return unless @nest_level.zero?

            was_active = @active
            @active = false
            should_stop = true
          end

          return unless should_stop

          on_stop if was_active
          flush_queued_messages
        end

        # Register a task for tracking (backward compatibility)
        # @param task_class [Class] The task class to register
        def register_task(task_class)
          @monitor.synchronize do
            return if @task_run_states.key?(task_class)

            @task_run_states[task_class] = :pending
            on_task_registered(task_class)
          end
        end

        # Check if a task is registered
        # @param task_class [Class] The task class to check
        # @return [Boolean] true if the task is registered
        def task_registered?(task_class)
          @monitor.synchronize { @task_run_states.key?(task_class) }
        end

        # Get the current state of a task
        # @param task_class [Class] The task class
        # @return [Symbol, nil] The task state or nil if not registered
        def task_state(task_class)
          @monitor.synchronize do
            @task_clean_states[task_class] || @task_run_states[task_class]
          end
        end

        # Unified task state update interface (the canonical Push API).
        # Receives state transitions from ExecutionContext.notify_task_updated.
        # Note: error is NOT passed via notification - exceptions propagate to top level (Plan design)
        # @param task_class [Class] The task class
        # @param previous_state [Symbol] The previous state
        # @param current_state [Symbol] The new state
        # @param timestamp [Time] When the transition occurred
        def on_task_updated(task_class, previous_state:, current_state:, timestamp:)
          @monitor.synchronize do
            phase = facade&.current_phase || :run
            duration = nil

            # Track start time and calculate duration
            @task_start_times[task_class] ||= {}
            if previous_state == :pending && current_state == :running
              @task_start_times[task_class][phase] = timestamp
            elsif %i[completed failed].include?(current_state)
              start_time = @task_start_times[task_class][phase]
              duration = ((timestamp - start_time) * 1000).round(1) if start_time
            end

            # Update state tracking
            if phase == :clean
              @task_clean_states[task_class] = current_state
              @task_durations[task_class] ||= {}
              @task_durations[task_class][:clean] = duration if duration
            else
              return if current_state == :running && %i[completed failed].include?(@task_run_states[task_class])

              @task_run_states[task_class] = current_state
              @task_durations[task_class] ||= {}
              @task_durations[task_class][:run] = duration if duration
            end

            render_task_state_change(task_class, phase, current_state, duration)
          end
        end

        # Register which impl was selected for a section (backward compatibility)
        # Section selection is now handled via on_task_updated (skipped state)
        def register_section_impl(section_class, impl_class)
          @monitor.synchronize do
            @task_run_states[impl_class] ||= :pending
            @task_run_states[section_class] = :completed if @task_run_states[section_class]
            on_section_impl_registered(section_class, impl_class)
          end
        end

        # Update group state for a task
        def update_group(task_class, group_name, state:, duration: nil, error: nil)
          @monitor.synchronize do
            on_group_updated(task_class, group_name, state, duration, error)
          end
        end

        # Queue a message to be displayed after progress display stops
        def queue_message(text)
          @monitor.synchronize { @message_queue << text }
        end

        # Render a Liquid template string with the given variables.
        def render_template_string(template_string, state: nil, task: nil, execution: nil, **variables)
          context_vars = build_context_vars(task:, execution:, **variables)
          template = Liquid::Template.parse(template_string, environment: @liquid_environment)
          template.assigns['state'] = state
          template.render(context_vars)
        end

        # Start the spinner animation timer.
        def start_spinner_timer
          @monitor.synchronize do
            return if @spinner_running

            @spinner_running = true
          end

          @spinner_timer = Thread.new do
            loop do
              running = @monitor.synchronize { @spinner_running }
              break unless running

              sleep @theme.spinner_interval
              @monitor.synchronize do
                @spinner_index = (@spinner_index + 1) % @theme.spinner_frames.size
              end
            end
          end
        end

        # Stop the spinner animation timer.
        def stop_spinner_timer
          @monitor.synchronize { @spinner_running = false }
          @spinner_timer&.join
          @spinner_timer = nil
        end

        # === Pull-based event handlers (TaskObserver interface) ===

        # Called when execution is ready (root task and dependencies resolved).
        # Pulls dependency_graph from facade for later use.
        def on_ready
          @root_task_class = facade&.root_task_class
          @dependency_graph = facade&.dependency_graph
        end

        protected

        # === Template methods - Override in subclasses ===

        def on_root_task_set
          # Default: no-op
        end

        def on_task_registered(task_class)
          # Default: no-op
        end

        def render_task_state_change(task_class, phase, state, duration)
          text = render_for_task_event(task_class, phase, state, duration)
          output_line(text) if text
        end

        def on_section_impl_registered(section_class, impl_class)
          # Default: no-op
        end

        def on_group_updated(task_class, group_name, state, duration, error)
          text = render_for_group_event(task_class, group_name, state, duration, error)
          output_line(text) if text
        end

        def should_activate?
          true
        end

        def on_start
          return unless @root_task_class

          output_line(render_execution_started(@root_task_class))
        end

        def on_stop
          output_line(render_execution_summary)
        end

        def render_execution_summary
          if failed_count.positive?
            render_execution_failed(failed_count: failed_count, total_count: total_count,
                                    total_duration: total_duration)
          else
            render_execution_completed(completed_count: completed_count, total_count: total_count,
                                       total_duration: total_duration)
          end
        end

        # === Template rendering helpers ===

        def render_task_template(method_name, task:, execution:)
          template_string = @theme.public_send(method_name)
          render_template_string(template_string, state: task.invoke_drop('state'), task:, execution:)
        end

        def render_execution_template(method_name, execution:, task: nil)
          template_string = @theme.public_send(method_name)
          render_template_string(template_string, state: execution.invoke_drop('state'), task:, execution:)
        end

        # === Event-to-template rendering methods ===

        def render_task_started(task_class)
          task = TaskDrop.new(name: task_class_name(task_class), state: :running)
          render_task_template(:task_start, task:, execution: execution_drop)
        end

        def render_task_succeeded(task_class, task_duration:)
          task = TaskDrop.new(name: task_class_name(task_class), state: :completed, duration: task_duration)
          render_task_template(:task_success, task:, execution: execution_drop)
        end

        def render_task_failed(task_class)
          # Note: error message is NOT available here - exceptions propagate to top level (Plan design)
          task = TaskDrop.new(name: task_class_name(task_class), state: :failed)
          render_task_template(:task_fail, task:, execution: execution_drop)
        end

        def render_task_skipped(task_class)
          task = TaskDrop.new(name: task_class_name(task_class), state: :skipped)
          render_task_template(:task_skipped, task:, execution: execution_drop)
        end

        def render_clean_started(task_class)
          task = TaskDrop.new(name: task_class_name(task_class), state: :running)
          render_task_template(:clean_start, task:, execution: execution_drop)
        end

        def render_clean_succeeded(task_class, task_duration:)
          task = TaskDrop.new(name: task_class_name(task_class), state: :completed, duration: task_duration)
          render_task_template(:clean_success, task:, execution: execution_drop)
        end

        def render_clean_failed(task_class)
          # Note: error message is NOT available here - exceptions propagate to top level (Plan design)
          task = TaskDrop.new(name: task_class_name(task_class), state: :failed)
          render_task_template(:clean_fail, task:, execution: execution_drop)
        end

        def render_group_started(task_class, group_name:)
          task = TaskDrop.new(name: task_class_name(task_class), state: :running, group_name:)
          render_task_template(:group_start, task:, execution: execution_drop)
        end

        def render_group_succeeded(task_class, group_name:, task_duration:)
          task = TaskDrop.new(name: task_class_name(task_class), state: :completed, group_name:,
                              duration: task_duration)
          render_task_template(:group_success, task:, execution: execution_drop)
        end

        def render_group_failed(task_class, group_name:, error:)
          task = TaskDrop.new(name: task_class_name(task_class), state: :failed, group_name:,
                              error_message: error&.message)
          render_task_template(:group_fail, task:, execution: execution_drop)
        end

        def render_execution_started(root_task_class)
          execution = ExecutionDrop.new(state: :running, root_task_name: task_class_name(root_task_class),
                                        **execution_context)
          render_execution_template(:execution_start, execution:)
        end

        def render_execution_completed(completed_count:, total_count:, total_duration:)
          execution = ExecutionDrop.new(state: :completed, completed_count:, total_count:, total_duration:)
          render_execution_template(:execution_complete, execution:)
        end

        def render_execution_failed(failed_count:, total_count:, total_duration:)
          execution = ExecutionDrop.new(state: :failed, failed_count:, total_count:, total_duration:)
          render_execution_template(:execution_fail, execution:)
        end

        def render_execution_running(done_count:, total_count:, task_names:, task_stdout:)
          task = TaskDrop.new(stdout: task_stdout)
          execution = ExecutionDrop.new(state: :running, done_count:, total_count:, task_names:)
          render_execution_template(:execution_running, execution:, task:)
        end

        def execution_context
          {
            state: execution_state,
            pending_count: pending_count,
            done_count: done_count,
            completed_count: completed_count,
            failed_count: failed_count,
            total_count: total_count,
            total_duration: total_duration,
            root_task_name: task_class_name(@root_task_class)
          }
        end

        def execution_state
          if failed_count.positive?
            :failed
          elsif done_count == total_count && total_count.positive?
            :completed
          else
            :running
          end
        end

        def execution_drop
          ExecutionDrop.new(**execution_context)
        end

        # === State-to-render dispatchers ===

        def render_for_task_event(task_class, phase, state, task_duration)
          if phase == :clean
            case state
            when :running
              render_clean_started(task_class)
            when :completed
              render_clean_succeeded(task_class, task_duration: task_duration)
            when :failed
              render_clean_failed(task_class)
            end
          else
            case state
            when :running
              render_task_started(task_class)
            when :completed
              render_task_succeeded(task_class, task_duration: task_duration)
            when :failed
              render_task_failed(task_class)
            when :skipped
              render_task_skipped(task_class)
            end
          end
        end

        def render_for_group_event(task_class, group_name, state, task_duration, error)
          case state
          when :running
            render_group_started(task_class, group_name: group_name)
          when :completed
            render_group_succeeded(task_class, group_name: group_name, task_duration: task_duration)
          when :failed
            render_group_failed(task_class, group_name: group_name, error: error)
          end
        end

        def output_line(text)
          @output.puts(text)
          @output.flush
        end

        # === Task state query helpers ===

        def running_tasks
          @task_run_states.select { |_, s| s == :running }
        end

        def cleaning_tasks
          @task_clean_states.select { |_, s| s == :running }
        end

        def pending_tasks
          @task_run_states.select { |_, s| s == :pending }
        end

        def completed_tasks
          @task_run_states.select { |_, s| s == :completed }
        end

        def failed_tasks
          @task_run_states.select { |_, s| s == :failed }
        end

        def pending_count
          @task_run_states.values.count(:pending)
        end

        def done_count
          @task_run_states.values.count { |s| %i[completed failed].include?(s) }
        end

        def completed_count
          @task_run_states.values.count(:completed)
        end

        def failed_count
          @task_run_states.values.count(:failed)
        end

        def total_count
          @task_run_states.size
        end

        def total_duration
          @start_time ? ((Time.now - @start_time) * 1000).to_i : 0
        end

        # === Utility methods ===

        def task_class_name(task_class)
          return nil unless task_class

          task_class.name || task_class.to_s
        end

        def tty?
          @output.tty?
        end

        def force_progress?
          ENV['TASKI_FORCE_PROGRESS'] == '1'
        end

        # Get stored duration for a task (for tree display)
        def task_duration(task_class, phase = :run)
          @task_durations.dig(task_class, phase)
        end

        private

        def build_liquid_environment
          Liquid::Environment.build do |env|
            env.register_filter(ColorFilter)
            env.register_tag('spinner', SpinnerTag)
            env.register_tag('icon', IconTag)
          end
        end

        def build_context_vars(variables)
          spinner_idx = @monitor.synchronize { @spinner_index }
          base_vars = {
            'template' => @theme_drop,
            'spinner_index' => variables[:spinner_index] || spinner_idx
          }
          stringify_keys(variables).merge(base_vars)
        end

        def stringify_keys(hash)
          hash.transform_keys(&:to_s)
        end

        def flush_queued_messages
          messages = @monitor.synchronize { @message_queue.dup.tap { @message_queue.clear } }
          messages.each { |msg| @output.puts(msg) }
        end
      end
    end
  end
end
