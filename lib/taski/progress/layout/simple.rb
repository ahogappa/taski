# frozen_string_literal: true

require_relative "base"
require_relative "../template/simple"

module Taski
  module Progress
    module Layout
      # Simple layout providing a minimalist single-line progress display.
      # Shows task execution status in a compact format with spinner animation:
      #
      #   ⠹ [3/5] DeployTask | Uploading files...
      #
      # Customization is done through Template classes:
      #
      #   class MyTemplate < Taski::Progress::Template::Base
      #     def spinner_frames
      #       %w[🌑 🌒 🌓 🌔 🌕 🌖 🌗 🌘]
      #     end
      #
      #     def icon_success
      #       "🎉"
      #     end
      #
      #     def format_count(count)
      #       "#{count}件"
      #     end
      #
      #     def status_complete
      #       '{% icon %} Done! {{ done_count | format_count }} tasks in {{ duration | format_duration }}'
      #     end
      #   end
      #
      #   layout = Taski::Progress::Layout::Simple.new(template: MyTemplate.new)
      class Simple < Base
        def initialize(output: $stdout, template: nil)
          template ||= Template::Simple.new
          super
          @renderer_thread = nil
          @running = false
        end

        protected

        # === Template method overrides ===

        def on_root_task_set
          build_tree_structure
        end

        # Simple layout uses periodic status line updates instead of per-event output
        def on_task_updated(_task_class, _state, _duration, _error)
          # No per-event output; status line is updated by render_live
        end

        def on_group_updated(_task_class, _group_name, _state, _duration, _error)
          # No per-event output; status line is updated by render_live
        end

        def should_activate?
          tty?
        end

        def on_start
          @running = true
          start_spinner_timer
          @output.print "\e[?25l"  # Hide cursor
          @renderer_thread = Thread.new do
            loop do
              break unless @running
              render_live
              sleep @template.render_interval
            end
          end
        end

        def on_stop
          @running = false
          @renderer_thread&.join
          stop_spinner_timer
          @output.print "\e[?25h"  # Show cursor
          render_final
        end

        private

        def build_tree_structure
          return unless @root_task_class

          tree = build_tree_node(@root_task_class)
          register_tasks_from_tree(tree)
          collect_section_candidates(tree)
        end

        # Register all tasks from a tree structure recursively
        def register_tasks_from_tree(node)
          return unless node

          task_class = node[:task_class]
          @tasks[task_class] ||= TaskState.new

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
            line = build_status_line
            # Clear line and write new content
            @output.print "\r\e[K#{line}"
            @output.flush
          end
        end

        def render_final
          @monitor.synchronize do
            line = if failed_count > 0
              first_error = failed_tasks.values.first&.run_error

              render_status_failed(
                done_count: completed_count,
                total: total_count,
                failed_task_name: short_name(failed_tasks.keys.first),
                error_message: first_error&.message
              )
            else
              render_status_completed(
                done_count: completed_count,
                total: total_count,
                duration: total_duration
              )
            end

            @output.print "\r\e[K#{line}\n"
            @output.flush
          end
        end

        def build_status_line
          task_names = collect_current_task_names

          primary_task = running_tasks.keys.first || cleaning_tasks.keys.first
          output_suffix = build_output_suffix(primary_task)

          render_status_running(
            done_count: done_count,
            total: total_count,
            task_names: task_names.empty? ? nil : task_names,
            output_suffix: output_suffix
          )
        end

        def collect_current_task_names
          # Prioritize: cleaning > running > pending
          current_tasks = if cleaning_tasks.any?
            cleaning_tasks.keys
          elsif running_tasks.any?
            running_tasks.keys
          elsif pending_tasks.any?
            pending_tasks.keys
          else
            []
          end

          current_tasks.map { |t| short_name(t) }
        end

        def build_output_suffix(task_class)
          return nil unless @output_capture && task_class

          last_line = @output_capture.last_line_for(task_class)
          return nil unless last_line && !last_line.strip.empty?

          last_line.strip
        end
      end
    end
  end
end
