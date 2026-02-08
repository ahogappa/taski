# frozen_string_literal: true

require "monitor"
require "liquid"
require_relative "../theme/default"
require_relative "../../execution/task_observer"
require_relative "filters"
require_relative "tags"
require_relative "theme_drop"

module Taski
  module Progress
    module Layout
      # Base class for layout implementations.
      # Layouts are responsible for:
      # - Receiving events from ExecutionFacade (Observer pattern)
      # - Managing task state tracking
      # - Rendering templates using Liquid
      # - Handling screen output
      #
      # === Observer Interface ===
      #
      # ExecutionFacade Event        | Observer Method      | Theme Method
      # -----------------------------|----------------------|----------------------------
      # notify_ready                 | on_ready             | (pulls root_task, output_capture)
      # notify_start                 | on_start             | execution_start
      # notify_stop                  | on_stop              | execution_complete/fail
      # notify_task_updated          | on_task_updated      | task_start/success/fail/skip/clean_*
      # notify_group_started         | on_group_started     | group_start
      # notify_group_completed       | on_group_completed   | group_success/fail
      class Base < Taski::Execution::TaskObserver
        attr_reader :spinner_index

        def initialize(output: $stderr, theme: nil)
          @output = output
          @context = nil
          @theme = theme || Theme::Default.new
          @theme_drop = ThemeDrop.new(@theme)
          @liquid_environment = build_liquid_environment
          @monitor = Monitor.new
          @tasks = {}
          @nest_level = 0
          @start_time = nil
          @root_task_class = nil
          @output_capture = nil
          @message_queue = []
          @spinner_index = 0
          @spinner_timer = nil
          @spinner_running = false
          @active = false
        end

        # === Observer Interface (called by ExecutionFacade) ===

        # Event 1: Facade is ready (root task set, output capture available).
        # Pulls root_task_class and output_capture from context.
        # Only sets root_task_class once (prevents nested executor overwrite).
        def on_ready
          @monitor.synchronize do
            return if @root_task_class
            @root_task_class = @context&.root_task_class
            @output_capture = @context&.output_capture
            handle_ready
          end
        end

        # Event 2: Start progress display.
        # Increments nest level for nested executor support.
        def on_start
          should_start = false
          @monitor.synchronize do
            @nest_level += 1
            return if @nest_level > 1
            return unless should_activate?
            @start_time = Time.now
            @active = true
            should_start = true
          end

          handle_start if should_start
        end

        # Event 3: Stop progress display.
        # Only finalizes when nest level reaches 0 and layout was actually activated.
        def on_stop
          should_stop = false
          was_active = false
          @monitor.synchronize do
            @nest_level -= 1 if @nest_level > 0
            return unless @nest_level == 0
            was_active = @active
            @active = false
            should_stop = true
          end

          return unless should_stop
          handle_stop if was_active
          flush_queued_messages
        end

        # Event 4: Task state transition.
        # @param task_class [Class]
        # @param previous_state [Symbol, nil]
        # @param current_state [Symbol]
        # @param phase [Symbol] :run or :clean
        # @param timestamp [Time]
        def on_task_updated(task_class, previous_state:, current_state:, phase:, timestamp:)
          @monitor.synchronize do
            progress = @tasks[task_class] ||= new_task_progress
            apply_state_transition(progress, current_state, phase, timestamp)
            handle_task_update(task_class, current_state, phase)
          end
        end

        # Event 7: Group started within a task.
        # @param task_class [Class]
        # @param group_name [String]
        # @param phase [Symbol] :run or :clean
        # @param timestamp [Time]
        def on_group_started(task_class, group_name, phase:, timestamp:)
          @monitor.synchronize do
            handle_group_started(task_class, group_name, phase)
          end
        end

        # Event 8: Group completed within a task.
        # @param task_class [Class]
        # @param group_name [String]
        # @param phase [Symbol] :run or :clean
        # @param timestamp [Time]
        def on_group_completed(task_class, group_name, phase:, timestamp:)
          @monitor.synchronize do
            handle_group_completed(task_class, group_name, phase)
          end
        end

        # Check if a task is registered
        # @param task_class [Class] The task class to check
        # @return [Boolean] true if the task is registered
        def task_registered?(task_class)
          @monitor.synchronize { @tasks.key?(task_class) }
        end

        # Get the current state of a task
        # @param task_class [Class] The task class
        # @return [Symbol, nil] The task state or nil if not registered
        def task_state(task_class)
          p = @monitor.synchronize { @tasks[task_class] }
          return nil unless p
          p[:clean_state] || p[:run_state]
        end

        # Queue a message to be displayed after progress display stops
        # Thread-safe for concurrent task execution
        # @param text [String] The message text to queue
        def queue_message(text)
          @monitor.synchronize { @message_queue << text }
        end

        # Render a Liquid template string with the given variables.
        # Uses scoped Liquid environment with ColorFilter and SpinnerTag.
        #
        # @param template_string [String] Liquid template string
        # @param state [Symbol, nil] State for icon tag
        # @param task [TaskDrop, nil] Task drop
        # @param execution [ExecutionDrop, nil] Execution drop
        # @return [String] Rendered output
        def render_template_string(template_string, state: nil, task: nil, execution: nil, **variables)
          context_vars = build_context_vars(task:, execution:, **variables)
          template = Liquid::Template.parse(template_string, environment: @liquid_environment)
          template.assigns["state"] = state
          template.render(context_vars)
        end

        # Start the spinner animation timer.
        # Increments spinner_index at the template's spinner_interval.
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

        protected

        # === Template methods - Override in subclasses ===

        # Called when facade is ready (root task and output capture available).
        # Override to build tree structure.
        def handle_ready
          # Default: no-op
        end

        # Called when a task state is updated.
        # Default: render and output the event.
        def handle_task_update(task_class, current_state, phase)
          progress = @tasks[task_class]
          duration = compute_duration(progress, phase)
          text = render_for_task_event(task_class, current_state, duration, nil, phase)
          output_line(text) if text
        end

        # Called when a group has started.
        # Default: render and output the event.
        def handle_group_started(task_class, group_name, phase)
          text = render_group_started(task_class, group_name: group_name)
          output_line(text) if text
        end

        # Called when a group has completed.
        # Default: render and output the event.
        def handle_group_completed(task_class, group_name, phase)
          text = render_group_succeeded(task_class, group_name: group_name, task_duration: nil)
          output_line(text) if text
        end

        # Register a task for tracking (used internally by subclasses like Tree).
        # @param task_class [Class] The task class to register
        def register_task(task_class)
          return if @tasks.key?(task_class)
          @tasks[task_class] = new_task_progress
        end

        # Determine if display should activate.
        # @return [Boolean] true if display should start
        def should_activate?
          true
        end

        # Called when display starts.
        # Default: output execution start message.
        def handle_start
          return unless @root_task_class
          output_line(render_execution_started(@root_task_class))
        end

        # Called when display stops.
        # Default: output execution complete or fail message.
        def handle_stop
          output_line(render_execution_summary)
        end

        # Render execution summary based on current state (success or failure)
        def render_execution_summary
          if failed_count > 0
            render_execution_failed(failed_count: failed_count, total_count: total_count, total_duration: total_duration, skipped_count: skipped_count)
          else
            render_execution_completed(completed_count: completed_count, total_count: total_count, total_duration: total_duration, skipped_count: skipped_count)
          end
        end

        # === Template rendering helpers ===

        # Render a task-level template with task and execution drops.
        # Uses task.state for icon tag.
        #
        # @param method_name [Symbol] The template method to call
        # @param task [TaskDrop] Task-level drop
        # @param execution [ExecutionDrop] Execution-level drop
        # @return [String] The rendered template
        def render_task_template(method_name, task:, execution:)
          template_string = @theme.public_send(method_name)
          render_template_string(template_string, state: task.invoke_drop("state"), task:, execution:)
        end

        # Render an execution-level template with execution drop only.
        # Uses execution.state for icon tag.
        #
        # @param method_name [Symbol] The template method to call
        # @param execution [ExecutionDrop] Execution-level drop
        # @param task [TaskDrop, nil] Optional task drop (for stdout in execution_running)
        # @return [String] The rendered template
        def render_execution_template(method_name, execution:, task: nil)
          template_string = @theme.public_send(method_name)
          render_template_string(template_string, state: execution.invoke_drop("state"), task:, execution:)
        end

        # === Event-to-template rendering methods ===
        # These methods define which template is used for each event.
        # Subclasses call these instead of render_template directly.
        #
        # Task-level methods pass both TaskDrop and ExecutionDrop so templates
        # can display progress like "[3/5] TaskName".
        # Execution-level methods pass only ExecutionDrop.

        # Render task start event
        def render_task_started(task_class)
          task = TaskDrop.new(name: task_class_name(task_class), state: :running)
          render_task_template(:task_start, task:, execution: execution_drop)
        end

        # Render task success event
        def render_task_succeeded(task_class, task_duration:)
          task = TaskDrop.new(name: task_class_name(task_class), state: :completed, duration: task_duration)
          render_task_template(:task_success, task:, execution: execution_drop)
        end

        # Render task failure event
        def render_task_failed(task_class, error:)
          task = TaskDrop.new(name: task_class_name(task_class), state: :failed, error_message: error&.message)
          render_task_template(:task_fail, task:, execution: execution_drop)
        end

        # Render task skipped event
        def render_task_skipped(task_class)
          task = TaskDrop.new(name: task_class_name(task_class), state: :skipped)
          render_task_template(:task_skip, task:, execution: execution_drop)
        end

        # Render clean start event (uses unified :running state)
        def render_clean_started(task_class)
          task = TaskDrop.new(name: task_class_name(task_class), state: :running)
          render_task_template(:clean_start, task:, execution: execution_drop)
        end

        # Render clean success event (uses unified :completed state)
        def render_clean_succeeded(task_class, task_duration:)
          task = TaskDrop.new(name: task_class_name(task_class), state: :completed, duration: task_duration)
          render_task_template(:clean_success, task:, execution: execution_drop)
        end

        # Render clean failure event (uses unified :failed state)
        def render_clean_failed(task_class, error:)
          task = TaskDrop.new(name: task_class_name(task_class), state: :failed, error_message: error&.message)
          render_task_template(:clean_fail, task:, execution: execution_drop)
        end

        # Render group start event
        def render_group_started(task_class, group_name:)
          task = TaskDrop.new(name: task_class_name(task_class), state: :running, group_name:)
          render_task_template(:group_start, task:, execution: execution_drop)
        end

        # Render group success event
        def render_group_succeeded(task_class, group_name:, task_duration:)
          task = TaskDrop.new(name: task_class_name(task_class), state: :completed, group_name:, duration: task_duration)
          render_task_template(:group_success, task:, execution: execution_drop)
        end

        # Render group failure event
        def render_group_failed(task_class, group_name:, error:)
          task = TaskDrop.new(name: task_class_name(task_class), state: :failed, group_name:, error_message: error&.message)
          render_task_template(:group_fail, task:, execution: execution_drop)
        end

        # Render execution start event
        def render_execution_started(root_task_class)
          execution = ExecutionDrop.new(state: :running, root_task_name: task_class_name(root_task_class), **execution_context)
          render_execution_template(:execution_start, execution:)
        end

        # Render execution complete event
        def render_execution_completed(completed_count:, total_count:, total_duration:, skipped_count: 0)
          execution = ExecutionDrop.new(state: :completed, completed_count:, total_count:, total_duration:, skipped_count:)
          render_execution_template(:execution_complete, execution:)
        end

        # Render execution failure event
        def render_execution_failed(failed_count:, total_count:, total_duration:, skipped_count: 0)
          execution = ExecutionDrop.new(state: :failed, failed_count:, total_count:, total_duration:, skipped_count:)
          render_execution_template(:execution_fail, execution:)
        end

        # Render execution running state (includes task for stdout display)
        def render_execution_running(done_count:, total_count:, task_names:, task_stdout:)
          task = TaskDrop.new(stdout: task_stdout)
          execution = ExecutionDrop.new(state: :running, done_count:, total_count:, task_names:)
          render_execution_template(:execution_running, execution:, task:)
        end

        # Returns current execution context as a hash
        def execution_context
          {
            state: execution_state,
            pending_count: pending_count,
            done_count: done_count,
            completed_count: completed_count,
            failed_count: failed_count,
            skipped_count: skipped_count,
            total_count: total_count,
            total_duration: total_duration,
            root_task_name: task_class_name(@root_task_class)
          }
        end

        # Returns current execution state
        def execution_state
          if failed_count > 0
            :failed
          elsif done_count == total_count && total_count > 0
            :completed
          else
            :running
          end
        end

        # Returns current execution context as an ExecutionDrop
        def execution_drop
          ExecutionDrop.new(**execution_context)
        end

        # === State-to-render dispatchers ===
        # These methods map state values to the appropriate render method.

        # Dispatch task event to appropriate render method
        # @return [String, nil] Rendered output or nil if state not handled
        def render_for_task_event(task_class, state, task_duration, error, phase = nil)
          if phase == :clean
            case state
            when :running
              render_clean_started(task_class)
            when :completed
              render_clean_succeeded(task_class, task_duration: task_duration)
            when :failed
              render_clean_failed(task_class, error: error)
            end
          else
            case state
            when :running
              render_task_started(task_class)
            when :completed
              render_task_succeeded(task_class, task_duration: task_duration)
            when :failed
              render_task_failed(task_class, error: error)
            when :skipped
              render_task_skipped(task_class)
            end
          end
        end

        # Dispatch group event to appropriate render method
        # @return [String, nil] Rendered output or nil if state not handled
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

        # Output a line to the output stream
        # @param text [String] The text to output
        def output_line(text)
          @output.puts(text)
          @output.flush
        end

        # === Task state query helpers ===

        def running_tasks
          @tasks.select { |_, p| p[:run_state] == :running }
        end

        def cleaning_tasks
          @tasks.select { |_, p| p[:clean_state] == :running }
        end

        def pending_tasks
          @tasks.select { |_, p| p[:run_state] == :pending }
        end

        def completed_tasks
          @tasks.select { |_, p| p[:run_state] == :completed }
        end

        def failed_tasks
          @tasks.select { |_, p| p[:run_state] == :failed }
        end

        def pending_count
          @tasks.values.count { |p| p[:run_state] == :pending }
        end

        def done_count
          @tasks.values.count { |p| [:completed, :failed, :skipped].include?(p[:run_state]) }
        end

        def skipped_count
          @tasks.values.count { |p| p[:run_state] == :skipped }
        end

        def completed_count
          @tasks.values.count { |p| p[:run_state] == :completed }
        end

        def failed_count
          @tasks.values.count { |p| p[:run_state] == :failed }
        end

        def total_count
          @tasks.size
        end

        def total_duration
          @start_time ? ((Time.now - @start_time) * 1000).to_i : 0
        end

        # === Utility methods ===

        # Get full name of a task class (for use with short_name filter in templates)
        def task_class_name(task_class)
          return nil unless task_class
          task_class.name || task_class.to_s
        end

        # Check if output is a TTY
        def tty?
          @output.tty?
        end

        private

        # Build the Liquid environment with filters and tags registered.
        # Uses scoped registration (not global) per Liquid 5.x recommendations.
        #
        # @return [Liquid::Environment] Configured Liquid environment
        def build_liquid_environment
          Liquid::Environment.build do |env|
            env.register_filter(ColorFilter)
            env.register_tag("spinner", SpinnerTag)
            env.register_tag("icon", IconTag)
          end
        end

        # Build context variables hash for Liquid rendering.
        #
        # @param variables [Hash] User-provided variables
        # @return [Hash] Context variables with template drop and spinner index
        def build_context_vars(variables)
          spinner_idx = @monitor.synchronize { @spinner_index }
          base_vars = {
            "template" => @theme_drop,
            "spinner_index" => variables[:spinner_index] || spinner_idx
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

        def new_task_progress
          {run_state: :pending, clean_state: nil, run_duration: nil, clean_duration: nil}
        end

        def compute_duration(progress, phase)
          return nil unless progress
          (phase == :clean) ? progress[:clean_duration] : progress[:run_duration]
        end

        # Apply state transition. Computes duration when transitioning out of :running.
        def apply_state_transition(progress, state, phase, timestamp)
          state_key, duration_key, started_key = if phase == :clean
            [:clean_state, :clean_duration, :_clean_started]
          else
            [:run_state, :run_duration, :_run_started]
          end

          case state
          when :running
            return if phase != :clean && run_state_terminal?(progress)
            progress[state_key] = :running
            progress[started_key] = timestamp
          when :completed, :failed
            progress[state_key] = state
            progress[duration_key] = duration_ms(progress[started_key], timestamp)
          when :skipped
            return if run_state_terminal?(progress)
            progress[state_key] = :skipped
          end
        end

        def run_state_terminal?(progress)
          [:completed, :failed, :skipped].include?(progress[:run_state])
        end

        def duration_ms(started, ended)
          (started && ended) ? ((ended - started) * 1000).round(1) : nil
        end
      end
    end
  end
end
