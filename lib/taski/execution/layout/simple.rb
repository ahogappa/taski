# frozen_string_literal: true

require_relative "base"

module Taski
  module Execution
    module Layout
      # Simple layout providing a minimalist single-line progress display.
      # Shows task execution status in a compact format with spinner animation:
      #
      #   ⠹ [3/5] DeployTask | Uploading files...
      #
      # Customization is done through Template classes:
      #
      #   class MyTemplate < Taski::Execution::Template::Base
      #     def spinner_frames
      #       %w[🌑 🌒 🌓 🌔 🌕 🌖 🌗 🌘]
      #     end
      #
      #     def icon_success
      #       "🎉"
      #     end
      #
      #     def simple_status_complete
      #       '{{ icon }} Done! {{ done_count }} tasks in {{ duration }}ms'
      #     end
      #   end
      #
      #   layout = Taski::Execution::Layout::Simple.new(template: MyTemplate.new)
      class Simple < Base
        def initialize(output: $stdout, template: nil)
          super
          @spinner_index = 0
          @renderer_thread = nil
          @running = false
          # Cache configuration from template for performance
          @spinner_frames = @template.spinner_frames
          @render_interval = @template.render_interval
        end

        protected

        # === Template method overrides ===

        def on_root_task_set
          build_tree_structure
        end

        def on_section_impl_registered(section_class, impl_class)
          @tasks[impl_class] ||= TaskState.new
          @tasks[impl_class].is_impl_candidate = false

          # Mark the section itself as completed (represented by its impl)
          @tasks[section_class]&.run_state = :completed

          mark_unselected_candidates_completed(section_class, impl_class)
        end

        def should_activate?
          tty?
        end

        def on_start
          @running = true
          @output.print "\e[?25l"  # Hide cursor
          @renderer_thread = Thread.new do
            loop do
              break unless @running
              render_live
              sleep @render_interval
            end
          end
        end

        def on_stop
          @running = false
          @renderer_thread&.join
          @output.print "\e[?25h"  # Show cursor
          render_final
        end

        private

        def build_tree_structure
          return unless @root_task_class

          # Use TreeProgressDisplay's static method for tree building if available
          if defined?(Taski::Execution::TreeProgressDisplay)
            tree = TreeProgressDisplay.build_tree_node(@root_task_class)
            register_tasks_from_tree(tree)
            collect_section_candidates(tree)
          else
            # Fallback: just register the root task
            @tasks[@root_task_class] ||= TaskState.new
          end
        end

        # Register all tasks from a tree structure recursively
        def register_tasks_from_tree(node)
          return unless node

          task_class = node[:task_class]
          @tasks[task_class] ||= TaskState.new
          @tasks[task_class].is_impl_candidate = true if node[:is_impl_candidate]

          node[:children].each { |child| register_tasks_from_tree(child) }
        end

        def collect_section_candidates(node)
          return unless node

          task_class = node[:task_class]

          # If this is a section, collect its implementation candidates and their subtrees
          if node[:is_section]
            candidate_nodes = node[:children].select { |c| c[:is_impl_candidate] }
            candidates = candidate_nodes.map { |c| c[:task_class] }
            @section_candidates[task_class] = candidates unless candidates.empty?

            # Store subtrees for each candidate
            subtrees = {}
            candidate_nodes.each { |c| subtrees[c[:task_class]] = c }
            @section_candidate_subtrees[task_class] = subtrees unless subtrees.empty?
          end

          node[:children].each { |child| collect_section_candidates(child) }
        end

        def render_live
          @monitor.synchronize do
            @spinner_index = (@spinner_index + 1) % @spinner_frames.size
            line = build_status_line
            # Clear line and write new content
            @output.print "\r\e[K#{line}"
            @output.flush
          end
        end

        def render_final
          @monitor.synchronize do
            total_duration = @start_time ? ((Time.now - @start_time) * 1000).to_i : 0
            completed = @tasks.values.count { |p| p.run_state == :completed }
            failed = @tasks.values.count { |p| p.run_state == :failed }
            total = @tasks.size

            line = if failed > 0
              failed_tasks = @tasks.select { |_, p| p.run_state == :failed }
              first_error = failed_tasks.values.first&.run_error
              icon = colorize(@template.icon_failure, :red)

              render_template(:simple_status_failed,
                icon: icon,
                done_count: completed,
                total: total,
                failed_task_name: short_name(failed_tasks.keys.first),
                error_message: first_error&.message)
            else
              icon = colorize(@template.icon_success, :green)

              render_template(:simple_status_complete,
                icon: icon,
                done_count: completed,
                total: total,
                duration: total_duration)
            end

            @output.print "\r\e[K#{line}\n"
            @output.flush
          end
        end

        def build_status_line
          running_tasks = @tasks.select { |_, p| p.run_state == :running }
          cleaning_tasks = @tasks.select { |_, p| p.clean_state == :cleaning }
          pending_tasks = @tasks.select { |_, p| p.run_state == :pending }
          failed_count = @tasks.values.count { |p| p.run_state == :failed }
          done_count = @tasks.values.count { |p| p.run_state == :completed || p.run_state == :failed }

          status_icon = determine_status_icon(failed_count, running_tasks, cleaning_tasks, pending_tasks)
          task_names = format_current_task_names(cleaning_tasks, running_tasks, pending_tasks)

          primary_task = running_tasks.keys.first || cleaning_tasks.keys.first
          output_suffix = build_output_suffix(primary_task)

          render_template(:simple_status_running,
            spinner: status_icon,
            done_count: done_count,
            total: @tasks.size,
            task_names: task_names.empty? ? nil : task_names,
            output_suffix: output_suffix)
        end

        def determine_status_icon(failed_count, running_tasks, cleaning_tasks, pending_tasks)
          if failed_count > 0
            colorize(@template.icon_failure, :red)
          elsif running_tasks.any? || cleaning_tasks.any? || pending_tasks.any?
            spinner = @spinner_frames[@spinner_index]
            colorize(spinner, :yellow)
          else
            colorize(@template.icon_success, :green)
          end
        end

        # Colorize text using Template's color configuration
        # @param text [String] The text to colorize
        # @param color_name [Symbol] The color name (:green, :red, :yellow)
        # @return [String] Colorized text
        def colorize(text, color_name)
          color = case color_name
          when :green then @template.color_green
          when :red then @template.color_red
          when :yellow then @template.color_yellow
          end
          "#{color}#{text}#{@template.color_reset}"
        end

        def format_current_task_names(cleaning_tasks, running_tasks, pending_tasks)
          # Prioritize: cleaning > running > pending
          current_tasks = if cleaning_tasks.any?
            cleaning_tasks.keys
          elsif running_tasks.any?
            running_tasks.keys
          elsif pending_tasks.any?
            pending_tasks.keys.first(3)
          else
            []
          end

          names = current_tasks.first(3).map { |t| short_name(t) }.join(", ")
          names += "..." if current_tasks.size > 3
          names
        end

        def build_output_suffix(task_class)
          return nil unless @output_capture && task_class

          last_line = @output_capture.last_line_for(task_class)
          return nil unless last_line && !last_line.strip.empty?

          # Truncate if too long
          max_length = 40
          if last_line.length > max_length
            last_line[0, max_length - 3] + "..."
          else
            last_line
          end
        end
      end
    end
  end
end
