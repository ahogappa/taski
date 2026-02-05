# frozen_string_literal: true

require 'monitor'
require 'liquid'
require_relative '../theme/default'
require_relative '../../static_analysis/analyzer'
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
      # - Managing task state tracking
      # - Rendering templates using Liquid
      # - Handling screen output
      #
      # === Event to Template Mapping (New Interface) ===
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
      #
      # === Legacy Interface (for backward compatibility) ===
      # update_task, register_task, etc. - kept for tests and gradual migration
      class Base < Taski::Execution::TaskObserver
        # Internal class to track task state
        class TaskState
          attr_accessor :run_state, :clean_state, :run_duration, :run_error, :clean_duration, :clean_error,
                        :run_started_at, :clean_started_at

          def initialize
            @run_state = :pending
            @clean_state = nil
            @run_started_at = nil
            @clean_started_at = nil
          end

          # Returns the most relevant state for display
          def state
            @clean_state || @run_state
          end
        end

        attr_reader :spinner_index

        def initialize(output: $stderr, theme: nil)
          @output = output
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
          @section_candidates = {}
          @section_candidate_subtrees = {}
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

        # Register a task for tracking
        # @param task_class [Class] The task class to register
        def register_task(task_class)
          @monitor.synchronize do
            return if @tasks.key?(task_class)

            @tasks[task_class] = TaskState.new
            on_task_registered(task_class)
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
          @monitor.synchronize { @tasks[task_class]&.state }
        end

        # Update task state (old interface, kept for backward compatibility).
        # Uses unified state names (:pending, :running, :completed, :failed, :skipped)
        # and determines phase from context.current_phase.
        # @param task_class [Class] The task class to update
        # @param state [Symbol] The unified state (:running, :completed, :failed, :skipped)
        # @param duration [Float, nil] Duration in milliseconds
        # @param error [Exception, nil] Error object for failed states
        def update_task(task_class, state:, duration: nil, error: nil)
          @monitor.synchronize do
            progress = @tasks[task_class]
            progress ||= @tasks[task_class] = TaskState.new

            # Get phase from context (defaults to :run if not set)
            phase = context&.current_phase || :run
            apply_state_transition(progress, phase, state, duration, error)
            render_task_state_change(task_class, phase, state, duration, error)
          end
        end

        # New unified task state update interface (Phase 5).
        # Receives state transitions from ExecutionContext.notify_task_updated.
        # Uses context.current_phase to determine if this is run or clean phase.
        # @param task_class [Class] The task class
        # @param previous_state [Symbol] The previous state
        # @param current_state [Symbol] The new state
        # @param timestamp [Time] When the transition occurred
        # @param error [Exception, nil] The error if state is :failed
        def on_task_updated(task_class, previous_state:, current_state:, timestamp:, error: nil)
          @monitor.synchronize do
            progress = @tasks[task_class]
            progress ||= @tasks[task_class] = TaskState.new

            # Determine if this is run or clean phase
            current_phase = context&.current_phase || :run

            duration = nil
            if current_phase == :clean
              # Clean phase handling - track timestamps and calculate duration
              if previous_state == :pending && current_state == :running
                progress.clean_started_at = timestamp
              elsif %i[completed failed].include?(current_state) && progress.clean_started_at
                duration = ((timestamp - progress.clean_started_at) * 1000).round(1)
              end
            elsif previous_state == :pending && current_state == :running
              # Run phase handling - track timestamps and calculate duration
              progress.run_started_at = timestamp
            elsif %i[completed failed].include?(current_state) && progress.run_started_at
              duration = ((timestamp - progress.run_started_at) * 1000).round(1)
            end

            # Apply state transition with unified state names
            apply_state_transition(progress, current_phase, current_state, duration, error)
            # Render with phase and unified state
            render_task_state_change(task_class, current_phase, current_state, duration, error)
          end
        end

        # Register which impl was selected for a section
        # @param section_class [Class] The section class
        # @param impl_class [Class] The selected implementation class
        def register_section_impl(section_class, impl_class)
          @monitor.synchronize do
            @tasks[impl_class] ||= TaskState.new

            # Mark section itself as completed
            @tasks[section_class].run_state = :completed if @tasks[section_class]

            mark_unselected_candidates_completed(section_class, impl_class)
            on_section_impl_registered(section_class, impl_class)
          end
        end

        # Update group state for a task
        # @param task_class [Class] The task class containing the group
        # @param group_name [String] The name of the group
        # @param state [Symbol] The new state (:running, :completed, :failed)
        # @param duration [Float, nil] Duration in milliseconds
        # @param error [Exception, nil] Error object for failed states
        def update_group(task_class, group_name, state:, duration: nil, error: nil)
          @monitor.synchronize do
            on_group_updated(task_class, group_name, state, duration, error)
          end
        end

        # Set the output capture for getting task output
        # @param capture [ThreadOutputCapture] The output capture instance
        def set_output_capture(capture)
          @monitor.synchronize { @output_capture = capture }
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
          template.assigns['state'] = state
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

        # Called when root task is set. Override to build tree structure.
        def on_root_task_set
          # Default: no-op
        end

        # Called when a task is registered.
        def on_task_registered(task_class)
          # Default: no-op
        end

        # Called internally when a task state is updated.
        # Default: render and output the event.
        # @param task_class [Class] The task class
        # @param phase [Symbol] :run or :clean
        # @param state [Symbol] Unified state: :pending, :running, :completed, :failed, :skipped
        # @param duration [Float, nil] Duration in ms
        # @param error [Exception, nil] Error if failed
        def render_task_state_change(task_class, phase, state, duration, error)
          text = render_for_task_event(task_class, phase, state, duration, error)
          output_line(text) if text
        end

        # Called when a section impl is registered.
        def on_section_impl_registered(section_class, impl_class)
          # Default: no-op
        end

        # Called when a group state is updated.
        # Default: render and output the event.
        def on_group_updated(task_class, group_name, state, duration, error)
          text = render_for_group_event(task_class, group_name, state, duration, error)
          output_line(text) if text
        end

        # Determine if display should activate.
        # @return [Boolean] true if display should start
        def should_activate?
          true
        end

        # Called when display starts.
        # Default: output execution start message.
        def on_start
          return unless @root_task_class

          output_line(render_execution_started(@root_task_class))
        end

        # Called when display stops.
        # Default: output execution complete or fail message.
        def on_stop
          output_line(render_execution_summary)
        end

        # Render execution summary based on current state (success or failure)
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

        # Render a task-level template with task and execution drops.
        # Uses task.state for icon tag.
        #
        # @param method_name [Symbol] The template method to call
        # @param task [TaskDrop] Task-level drop
        # @param execution [ExecutionDrop] Execution-level drop
        # @return [String] The rendered template
        def render_task_template(method_name, task:, execution:)
          template_string = @theme.public_send(method_name)
          render_template_string(template_string, state: task.invoke_drop('state'), task:, execution:)
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
          render_template_string(template_string, state: execution.invoke_drop('state'), task:, execution:)
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
          render_task_template(:task_skipped, task:, execution: execution_drop)
        end

        # Render clean start event
        def render_clean_started(task_class)
          task = TaskDrop.new(name: task_class_name(task_class), state: :running)
          render_task_template(:clean_start, task:, execution: execution_drop)
        end

        # Render clean success event
        def render_clean_succeeded(task_class, task_duration:)
          task = TaskDrop.new(name: task_class_name(task_class), state: :completed, duration: task_duration)
          render_task_template(:clean_success, task:, execution: execution_drop)
        end

        # Render clean failure event
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
          task = TaskDrop.new(name: task_class_name(task_class), state: :completed, group_name:,
                              duration: task_duration)
          render_task_template(:group_success, task:, execution: execution_drop)
        end

        # Render group failure event
        def render_group_failed(task_class, group_name:, error:)
          task = TaskDrop.new(name: task_class_name(task_class), state: :failed, group_name:,
                              error_message: error&.message)
          render_task_template(:group_fail, task:, execution: execution_drop)
        end

        # Render execution start event
        def render_execution_started(root_task_class)
          execution = ExecutionDrop.new(state: :running, root_task_name: task_class_name(root_task_class),
                                        **execution_context)
          render_execution_template(:execution_start, execution:)
        end

        # Render execution complete event
        def render_execution_completed(completed_count:, total_count:, total_duration:)
          execution = ExecutionDrop.new(state: :completed, completed_count:, total_count:, total_duration:)
          render_execution_template(:execution_complete, execution:)
        end

        # Render execution failure event
        def render_execution_failed(failed_count:, total_count:, total_duration:)
          execution = ExecutionDrop.new(state: :failed, failed_count:, total_count:, total_duration:)
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
            total_count: total_count,
            total_duration: total_duration,
            root_task_name: task_class_name(@root_task_class)
          }
        end

        # Returns current execution state
        def execution_state
          if failed_count.positive?
            :failed
          elsif done_count == total_count && total_count.positive?
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
        # Dispatch task event to appropriate render method based on phase and state
        # @param task_class [Class] The task class
        # @param phase [Symbol] :run or :clean
        # @param state [Symbol] Unified state: :running, :completed, :failed, :skipped
        # @param task_duration [Float, nil] Duration in ms
        # @param error [Exception, nil] Error if failed
        # @return [String, nil] Rendered output or nil if state not handled
        def render_for_task_event(task_class, phase, state, task_duration, error)
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
          @tasks.select { |_, p| p.run_state == :running }
        end

        def cleaning_tasks
          # Phase 1: clean_state now uses unified :running value
          @tasks.select { |_, p| p.clean_state == :running }
        end

        def pending_tasks
          @tasks.select { |_, p| p.run_state == :pending }
        end

        def completed_tasks
          @tasks.select { |_, p| p.run_state == :completed }
        end

        def failed_tasks
          @tasks.select { |_, p| p.run_state == :failed }
        end

        def pending_count
          @tasks.values.count { |p| p.run_state == :pending }
        end

        def done_count
          @tasks.values.count { |p| %i[completed failed].include?(p.run_state) }
        end

        def completed_count
          @tasks.values.count { |p| p.run_state == :completed }
        end

        def failed_count
          @tasks.values.count { |p| p.run_state == :failed }
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

        # Check if progress display should be forced regardless of TTY
        def force_progress?
          ENV['TASKI_FORCE_PROGRESS'] == '1'
        end

        # Collect all dependencies of a task class recursively
        # @param task_class [Class] The task class
        # @return [Set<Class>] Set of all dependency task classes
        def collect_all_dependencies(task_class)
          deps = Set.new
          collect_dependencies_recursive(task_class, deps)
          deps
        end

        private

        # Build the Liquid environment with filters and tags registered.
        # Uses scoped registration (not global) per Liquid 5.x recommendations.
        #
        # @return [Liquid::Environment] Configured Liquid environment
        def build_liquid_environment
          Liquid::Environment.build do |env|
            env.register_filter(ColorFilter)
            env.register_tag('spinner', SpinnerTag)
            env.register_tag('icon', IconTag)
          end
        end

        # Build context variables hash for Liquid rendering.
        #
        # @param variables [Hash] User-provided variables
        # @return [Hash] Context variables with template drop and spinner index
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

        # Apply state transition to TaskState
        # Once a task reaches :completed or :failed, it cannot go back to :running
        # (prevents progress count from decreasing when nested executors re-execute)
        # @param progress [TaskState] The task state object
        # @param phase [Symbol] :run or :clean
        # @param state [Symbol] Unified state: :pending, :running, :completed, :failed, :skipped
        # @param duration [Float, nil] Duration in ms
        # @param error [Exception, nil] Error if failed
        def apply_state_transition(progress, phase, state, duration, error)
          if phase == :clean
            case state
            when :pending
              progress.clean_state = :pending
            when :running
              progress.clean_state = :running
            when :completed
              progress.clean_state = :completed
              progress.clean_duration = duration if duration
            when :failed
              progress.clean_state = :failed
              progress.clean_error = error if error
            end
          else
            # Run phase
            case state
            when :pending
              progress.run_state = :pending
            when :running
              return if run_state_finalized?(progress)

              progress.run_state = :running
            when :completed
              progress.run_state = :completed
              progress.run_duration = duration if duration
            when :failed
              progress.run_state = :failed
              progress.run_error = error if error
            when :skipped
              progress.run_state = :skipped
            end
          end
        end

        def run_state_finalized?(progress)
          %i[completed failed].include?(progress.run_state)
        end

        def collect_dependencies_recursive(task_class, collected)
          return if collected.include?(task_class)

          collected.add(task_class)

          return unless task_class.respond_to?(:cached_dependencies)

          task_class.cached_dependencies.each do |dep|
            collect_dependencies_recursive(dep, collected)
          end
        end

        # Mark unselected candidates and their exclusive subtrees as completed (skipped)
        def mark_unselected_candidates_completed(section_class, impl_class)
          selected_deps = collect_all_dependencies(impl_class)
          candidates = @section_candidates[section_class] || []
          subtrees = @section_candidate_subtrees[section_class] || {}

          candidates.each do |candidate|
            next if candidate == impl_class

            mark_subtree_completed(subtrees[candidate], exclude: selected_deps)
          end
        end

        # Recursively mark all pending tasks in a subtree as completed (skipped)
        def mark_subtree_completed(node, exclude: Set.new)
          return unless node

          task_class = node[:task_class]
          mark_task_as_skipped(task_class) unless exclude.include?(task_class)
          node[:children].each { |child| mark_subtree_completed(child, exclude: exclude) }
        end

        def mark_task_as_skipped(task_class)
          progress = @tasks[task_class]
          progress.run_state = :skipped if progress&.run_state == :pending
        end

        # === Tree building helpers ===
        # TODO: Move to ExecutionContext (see #149)
        # These methods are here temporarily. Layout should not analyze task dependencies.

        # Collect section candidates from a tree structure.
        # Populates @section_candidates and @section_candidate_subtrees.
        # @param node [Hash] Tree node
        def collect_section_candidates(node)
          return unless node

          task_class = node[:task_class]

          if node[:is_section]
            candidate_nodes = node[:children].select { |c| c[:is_impl_candidate] }
            candidates = candidate_nodes.map { |c| c[:task_class] }
            @section_candidates[task_class] = candidates unless candidates.empty?

            subtrees = {}
            candidate_nodes.each { |c| subtrees[c[:task_class]] = c }
            @section_candidate_subtrees[task_class] = subtrees unless subtrees.empty?
          end

          node[:children].each { |child| collect_section_candidates(child) }
        end

        # Build a tree structure from a root task class.
        # @param task_class [Class] The root task class
        # @param ancestors [Set] Set of ancestor classes (for circular detection)
        # @return [Hash] Tree node hash
        def build_tree_node(task_class, ancestors = Set.new)
          is_circular = ancestors.include?(task_class)

          node = {
            task_class: task_class,
            is_section: section_class?(task_class),
            is_circular: is_circular,
            is_impl_candidate: false,
            children: []
          }

          return node if is_circular

          new_ancestors = ancestors + [task_class]
          dependencies = get_task_dependencies(task_class)
          is_section = section_class?(task_class)

          dependencies.each do |dep|
            child_node = build_tree_node(dep, new_ancestors)
            child_node[:is_impl_candidate] = is_section && nested_class?(dep, task_class)
            node[:children] << child_node
          end

          node
        end

        # Get dependencies for a task class.
        # Tries static analysis first, falls back to cached_dependencies.
        # @param task_class [Class] The task class
        # @return [Array<Class>] Array of dependency classes
        def get_task_dependencies(task_class)
          deps = Taski::StaticAnalysis::Analyzer.analyze(task_class).to_a
          return deps unless deps.empty?

          # Fallback to cached_dependencies for test stubs
          if task_class.respond_to?(:cached_dependencies)
            task_class.cached_dependencies
          else
            []
          end
        end

        # Check if a class is a Taski::Section subclass.
        def section_class?(klass)
          defined?(Taski::Section) && klass < Taski::Section
        end

        # Check if a class is nested within another class by name prefix.
        # Returns false for anonymous classes (nil or empty names).
        def nested_class?(child_class, parent_class)
          parent_name = parent_class.name
          child_name = child_class.name
          return false if parent_name.nil? || parent_name.empty?
          return false if child_name.nil? || child_name.empty?

          child_name.start_with?("#{parent_name}::")
        end
      end
    end
  end
end
