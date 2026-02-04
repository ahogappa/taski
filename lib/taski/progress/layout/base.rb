# frozen_string_literal: true

require "monitor"
require "liquid"
require_relative "../template/default"
require_relative "../../static_analysis/analyzer"
require_relative "filters"
require_relative "tags"
require_relative "template_drop"

module Taski
  module Progress
    module Layout
      # Base class for layout implementations.
      # Layouts are responsible for:
      # - Receiving events from ExecutionContext (Observer pattern)
      # - Managing task state tracking
      # - Rendering templates using Liquid
      # - Handling screen output
      #
      # === Event to Template Mapping ===
      #
      # ExecutionContext Event              | Layout Method              | Template Method
      # ------------------------------------|----------------------------|---------------------------
      # notify_set_root_task                | set_root_task              | execution_start
      # notify_start                        | start                      | (internal setup)
      # notify_stop                         | stop                       | execution_complete/fail
      # notify_task_registered              | register_task              | (state tracking)
      # notify_task_started (:running)      | update_task                | task_start
      # notify_task_completed (:completed)  | update_task                | task_success
      # notify_task_completed (:failed)     | update_task                | task_fail
      # notify_clean_started (:cleaning)    | update_task                | clean_start
      # notify_clean_completed (:clean_*)   | update_task                | clean_success/fail
      # notify_section_impl_selected        | register_section_impl      | (skip handling)
      # notify_group_started                | update_group               | group_start
      # notify_group_completed              | update_group               | group_success/fail
      class Base
        # Internal class to track task state
        class TaskState
          attr_accessor :run_state, :clean_state
          attr_accessor :run_duration, :run_error
          attr_accessor :clean_duration, :clean_error

          def initialize
            @run_state = :pending
            @clean_state = nil
          end

          # Returns the most relevant state for display
          def state
            @clean_state || @run_state
          end
        end

        attr_reader :spinner_index

        def initialize(output: $stderr, template: nil)
          @output = output
          @template = template || Template::Default.new
          @template_drop = TemplateDrop.new(@template)
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
            @nest_level -= 1 if @nest_level > 0
            return unless @nest_level == 0
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

        # Update task state
        # @param task_class [Class] The task class to update
        # @param state [Symbol] The new state (:running, :completed, :failed, :cleaning, :clean_completed, :clean_failed)
        # @param duration [Float, nil] Duration in milliseconds
        # @param error [Exception, nil] Error object for failed states
        def update_task(task_class, state:, duration: nil, error: nil)
          @monitor.synchronize do
            progress = @tasks[task_class]
            progress ||= @tasks[task_class] = TaskState.new
            apply_state_transition(progress, state, duration, error)
            on_task_updated(task_class, state, duration, error)
          end
        end

        # Register which impl was selected for a section
        # @param section_class [Class] The section class
        # @param impl_class [Class] The selected implementation class
        def register_section_impl(section_class, impl_class)
          @monitor.synchronize do
            @tasks[impl_class] ||= TaskState.new

            # Mark section itself as completed
            if @tasks[section_class]
              @tasks[section_class].run_state = :completed
            end

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
        # @param variables [Hash] Variables to pass to the template
        # @return [String] Rendered output
        def render_template_string(template_string, **variables)
          context_vars = build_context_vars(variables)
          Liquid::Template.parse(template_string, environment: @liquid_environment)
            .render(context_vars)
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
              sleep @template.spinner_interval
              @monitor.synchronize do
                @spinner_index = (@spinner_index + 1) % @template.spinner_frames.size
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

        # Called when a task state is updated.
        # Default: render and output the event.
        def on_task_updated(task_class, state, duration, error)
          text = render_for_task_event(task_class, state, duration, error)
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
          duration = total_duration

          text = if failed_count > 0
            render_execution_failed(failed: failed_count, total: total_count, duration: duration)
          else
            render_execution_completed(completed: completed_count, total: total_count, duration: duration)
          end
          output_line(text)
        end

        # === Template rendering helpers ===

        # Render a template method with the given variables
        # Common variables available in all templates.
        # Values default to nil if not provided.
        COMMON_TEMPLATE_VARIABLES = %i[
          task_name
          state
          duration
          error_message
          done_count
          completed
          failed
          total
          root_task_name
          group_name
          task_names
          output_suffix
        ].freeze

        # @param method_name [Symbol] The template method to call
        # @param variables [Hash] Variables to pass to the template
        # @return [String] The rendered template
        def render_template(method_name, **variables)
          # Merge with common variables (nil defaults)
          common_vars = COMMON_TEMPLATE_VARIABLES.to_h { |k| [k, nil] }
          merged_vars = common_vars.merge(variables)
          template_string = @template.public_send(method_name)
          render_template_string(template_string, **merged_vars)
        end

        # === Event-to-template rendering methods ===
        # These methods define which template is used for each event.
        # Subclasses call these instead of render_template directly.

        # Render task start event
        def render_task_started(task_class)
          render_template(:task_start, task_name: short_name(task_class), state: :running)
        end

        # Render task success event
        def render_task_succeeded(task_class, duration:)
          render_template(:task_success, task_name: short_name(task_class), duration: duration, state: :completed)
        end

        # Render task failure event
        def render_task_failed(task_class, error:)
          render_template(:task_fail, task_name: short_name(task_class), error_message: error&.message, state: :failed)
        end

        # Render clean start event
        def render_clean_started(task_class)
          render_template(:clean_start, task_name: short_name(task_class))
        end

        # Render clean success event
        def render_clean_succeeded(task_class, duration:)
          render_template(:clean_success, task_name: short_name(task_class), duration: duration)
        end

        # Render clean failure event
        def render_clean_failed(task_class, error:)
          render_template(:clean_fail, task_name: short_name(task_class), error_message: error&.message)
        end

        # Render group start event
        def render_group_started(task_class, group_name:)
          render_template(:group_start, task_name: short_name(task_class), group_name: group_name)
        end

        # Render group success event
        def render_group_succeeded(task_class, group_name:, duration:)
          render_template(:group_success, task_name: short_name(task_class), group_name: group_name, duration: duration)
        end

        # Render group failure event
        def render_group_failed(task_class, group_name:, error:)
          render_template(:group_fail, task_name: short_name(task_class), group_name: group_name, error_message: error&.message)
        end

        # Render execution start event
        def render_execution_started(root_task_class)
          render_template(:execution_start, root_task_name: short_name(root_task_class))
        end

        # Render execution complete event
        def render_execution_completed(completed:, total:, duration:)
          render_template(:execution_complete, completed: completed, total: total, duration: duration, state: :completed)
        end

        # Render execution failure event
        def render_execution_failed(failed:, total:, duration:)
          render_template(:execution_fail, failed: failed, total: total, duration: duration, state: :failed)
        end

        # Render execution running state
        def render_execution_running(done_count:, total:, task_names:, output_suffix:)
          render_template(:execution_running,
            done_count: done_count,
            total: total,
            task_names: task_names,
            output_suffix: output_suffix,
            state: :running)
        end

        # === State-to-render dispatchers ===
        # These methods map state values to the appropriate render method.

        # Dispatch task event to appropriate render method
        # @return [String, nil] Rendered output or nil if state not handled
        def render_for_task_event(task_class, state, duration, error)
          case state
          when :running
            render_task_started(task_class)
          when :completed
            render_task_succeeded(task_class, duration: duration)
          when :failed
            render_task_failed(task_class, error: error)
          when :cleaning
            render_clean_started(task_class)
          when :clean_completed
            render_clean_succeeded(task_class, duration: duration)
          when :clean_failed
            render_clean_failed(task_class, error: error)
          end
        end

        # Dispatch group event to appropriate render method
        # @return [String, nil] Rendered output or nil if state not handled
        def render_for_group_event(task_class, group_name, state, duration, error)
          case state
          when :running
            render_group_started(task_class, group_name: group_name)
          when :completed
            render_group_succeeded(task_class, group_name: group_name, duration: duration)
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
          @tasks.select { |_, p| p.clean_state == :cleaning }
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

        def done_count
          @tasks.values.count { |p| p.run_state == :completed || p.run_state == :failed }
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

        # Get short name of a task class
        def short_name(task_class)
          return "Unknown" unless task_class
          task_class.name&.split("::")&.last || task_class.to_s
        end

        # Format duration for display
        def format_duration(ms)
          return nil unless ms
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

        # Check if progress display should be forced regardless of TTY
        def force_progress?
          ENV["TASKI_FORCE_PROGRESS"] == "1"
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
            "template" => @template_drop,
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

        # Apply state transition to TaskState
        # Once a task reaches :completed or :failed, it cannot go back to :running
        # (prevents progress count from decreasing when nested executors re-execute)
        def apply_state_transition(progress, state, duration, error)
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
          when :cleaning
            progress.clean_state = :cleaning
          when :clean_completed
            progress.clean_state = :clean_completed
            progress.clean_duration = duration if duration
          when :clean_failed
            progress.clean_state = :clean_failed
            progress.clean_error = error if error
          end
        end

        def run_state_finalized?(progress)
          progress.run_state == :completed || progress.run_state == :failed
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
          progress.run_state = :completed if progress&.run_state == :pending
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
