# frozen_string_literal: true

require_relative 'base'
require_relative '../theme/compact'

module Taski
  module Progress
    module Layout
      # Simple layout providing a minimalist single-line progress display.
      # Shows task execution status in a compact format with spinner animation:
      #
      #   ⠹ [3/5] DeployTask | Uploading files...
      #
      # Customization is done through Theme classes:
      #
      #   class MyTheme < Taski::Progress::Theme::Base
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
      #   layout = Taski::Progress::Layout::Simple.new(theme: MyTheme.new)
      class Simple < Base
        def initialize(output: $stdout, theme: nil)
          theme ||= Theme::Compact.new
          super
          @renderer_thread = nil
          @running = false
          @running_mutex = Mutex.new
        end

        protected

        # === Template method overrides ===

        # Override to build tree structure after dependency_graph is available
        def on_ready
          super
          build_tree_structure
        end

        def on_root_task_set
          # Tree structure is built in on_ready after dependency_graph is available
        end

        # Simple layout uses periodic status line updates instead of per-event output
        def render_task_state_change(_task_class, _phase, _state, _duration)
          # No per-event output; status line is updated by render_live
        end

        def on_group_updated(_task_class, _group_name, _state, _duration, _error)
          # No per-event output; status line is updated by render_live
        end

        def should_activate?
          force_progress? || tty?
        end

        def on_start
          @running_mutex.synchronize { @running = true }
          start_spinner_timer
          @output.print "\e[?25l"  # Hide cursor
          @renderer_thread = Thread.new do
            loop do
              break unless @running_mutex.synchronize { @running }

              render_live
              sleep @theme.render_interval
            end
          end
        end

        def on_stop
          @running_mutex.synchronize { @running = false }
          @renderer_thread&.join
          stop_spinner_timer
          @output.print "\e[?25h"  # Show cursor
          render_final
        end

        private

        def build_tree_structure
          return unless @root_task_class
          return unless @dependency_graph

          # Register all tasks from dependency graph
          register_tasks_from_graph(@root_task_class)
        end

        def register_tasks_from_graph(task_class, visited = Set.new)
          return if visited.include?(task_class)

          visited.add(task_class)
          @task_run_states[task_class] ||= :pending

          dependencies = @dependency_graph.dependencies_for(task_class)
          dependencies.each { |dep| register_tasks_from_graph(dep, visited) }
        end

        def render_live
          @monitor.synchronize do
            line = build_status_line
            # Truncate line to terminal width to prevent line wrap
            max_width = terminal_width - 1 # Leave space for cursor
            line = line[0, max_width] if line.length > max_width
            # Clear line and write new content
            @output.print "\r\e[K#{line}"
            @output.flush
          end
        end

        def terminal_width
          @output.winsize[1]
        rescue StandardError
          80 # Default fallback
        end

        def render_final
          @monitor.synchronize do
            line = if failed_count.positive?
                     render_execution_failed(failed_count: failed_count, total_count: total_count,
                                             total_duration: total_duration)
                   else
                     render_execution_completed(completed_count: completed_count, total_count: total_count,
                                                total_duration: total_duration)
                   end

            @output.print "\r\e[K#{line}\n"
            @output.flush
          end
        end

        def build_status_line
          task_names = collect_current_task_names

          primary_task = running_tasks.keys.first || cleaning_tasks.keys.first
          task_stdout = build_task_stdout(primary_task)

          render_execution_running(
            done_count: done_count,
            total_count: total_count,
            task_names: task_names.empty? ? nil : task_names,
            task_stdout: task_stdout
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

          current_tasks.map { |t| task_class_name(t) }
        end

        def build_task_stdout(task_class)
          return nil unless @output_capture && task_class

          last_line = @output_capture.last_line_for(task_class)
          return nil unless last_line && !last_line.strip.empty?

          last_line.strip
        end
      end
    end
  end
end
