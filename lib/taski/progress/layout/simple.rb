# frozen_string_literal: true

require_relative "base"
require_relative "../theme/compact"

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
      #     def execution_complete(execution:, task: nil)
      #       "#{icon_for(execution.state)} Done! #{format_count(execution.done_count)} tasks in #{format_duration(execution.total_duration)}"
      #     end
      #   end
      #
      #   Taski.progress.layout = Taski::Progress::Layout::Simple
      #   Taski.progress.theme = MyTheme
      module Simple
        # Build the single-line display (Simple has a single implementation).
        # @return [Simple::Display]
        def self.build(output: $stdout, theme: nil)
          Display.new(output: output, theme: theme)
        end

        class Display < Base
          def initialize(output: $stdout, theme: nil)
            theme ||= Theme::Compact.new
            super
            # Per-task snapshot of the last captured output line at the moment
            # the current group opened (see handle_group_started).
            @group_baselines = {}
          end

          protected

          # === Template method overrides ===

          def handle_ready
            graph = context&.dependency_graph
            return unless graph

            graph.all_tasks.each { |tc| register_task(tc) }
          end

          # Drop the previous execution's group baselines when a new top-level
          # execution reuses this display.
          def handle_reset
            @group_baselines.clear
            super
          end

          # Simple layout uses periodic status line updates instead of per-event output
          def handle_task_update(_task_class, _current_state, _phase)
            # No per-event output; status line is updated by render_live
          end

          # No per-event output, but record which captured line was current
          # when the group opened: the status line must not caption a line
          # emitted BEFORE the group with the new group's name (a quiet group
          # would otherwise show the previous phase's output as its own).
          # Called under @monitor (Layout::Base#on_group_started).
          def handle_group_started(task_class, _group_name, _phase)
            @group_baselines[task_class] = @output_capture&.last_line_for(task_class)
          end

          def handle_group_completed(task_class, _group_name, _phase, _duration)
            if active_group_name(task_class)
              # An enclosing group is still open: re-baseline so it only
              # captions output emitted from now on.
              @group_baselines[task_class] = @output_capture&.last_line_for(task_class)
            else
              @group_baselines.delete(task_class)
            end
          end

          def should_activate?
            tty?
          end

          def handle_start
            @output.print "\e[?25l"  # Hide cursor
            render_loop { render_status_line }
          end

          def handle_stop
            stop_render_loop
            @output.print "\e[?25h"  # Show cursor
            render_final
          rescue IOError, SystemCallError
            # The terminal is gone — there is nothing left to restore or render
            # to. Contain the error so on_stop still flushes queued messages.
          end

          private

          def render_status_line
            line = build_status_line
            # Truncate line to terminal width to prevent line wrap
            max_width = terminal_width - 1  # Leave space for cursor
            line = line[0, max_width] if line.length > max_width
            # Clear line and write new content
            @output.print "\r\e[K#{line}"
            @output.flush
          end

          def terminal_width
            @output.winsize[1]
          rescue
            80 # Default fallback
          end

          def render_final
            @monitor.synchronize do
              line = if failed_count > 0
                render_execution_failed(failed_count: failed_count, total_count: total_count, total_duration: total_duration, skipped_count: skipped_count)
              else
                render_execution_completed(done_count: done_count, total_count: total_count, total_duration: total_duration, skipped_count: skipped_count)
              end

              @output.print "\r\e[K#{line}\n"
              @output.flush
            end
          end

          def build_status_line
            task_names = collect_current_task_names

            primary_task = running_tasks.keys.last || cleaning_tasks.keys.last
            task_stdout = build_task_stdout(primary_task)

            render_execution_running(
              done_count: done_count,
              total_count: total_count,
              task_names: task_names.empty? ? nil : task_names,
              task_stdout: with_group_prefix(primary_task, task_stdout)
            )
          end

          # Max characters of group name shown when combined with output, so
          # a long group name cannot starve the stdout budget downstream
          # (the combined string is truncated to truncate_text_max).
          GROUP_LABEL_MAX = 15

          # While a group block is open, show which phase is executing:
          # "GroupName: output..." — or the group name alone until the group
          # emits its first line (output captured before the group opened is
          # not the group's; see handle_group_started). Documented in the
          # GUIDE's Group Blocks section.
          def with_group_prefix(task_class, task_stdout)
            group = task_class ? active_group_name(task_class) : nil
            return task_stdout unless group

            task_stdout = nil if task_stdout == @group_baselines[task_class]&.strip
            return group unless task_stdout

            "#{group_label(group)}: #{task_stdout}"
          end

          def group_label(group)
            return group if group.length <= GROUP_LABEL_MAX
            suffix = @theme.truncate_text_suffix
            group[0, [GROUP_LABEL_MAX - suffix.length, 1].max] + suffix
          end

          def collect_current_task_names
            # Prioritize: cleaning > running > pending
            # Reverse so most recently started tasks appear first
            current_tasks = if cleaning_tasks.any?
              cleaning_tasks.keys.reverse
            elsif running_tasks.any?
              running_tasks.keys.reverse
            elsif pending_tasks.any?
              pending_tasks.keys.reverse
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
end
