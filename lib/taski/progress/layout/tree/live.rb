# frozen_string_literal: true

require_relative "../base"
require_relative "../../theme/detail"
require_relative "structure"

module Taski
  module Progress
    module Layout
      module Tree
        # TTY periodic-update tree layout.
        # Refreshes the entire tree display at regular intervals with spinner animation.
        # Used for interactive terminal output.
        class Live < Base
          include Structure

          def initialize(output: $stderr, theme: nil)
            theme ||= Theme::Detail.new
            super
            init_tree_structure
            @last_line_count = 0
          end

          protected

          def handle_ready
            build_ready_tree
          end

          # TTY mode: skip per-event output, tree is updated by render_loop
          def handle_task_update(_task_class, _current_state, _phase)
          end

          def handle_group_started(_task_class, _group_name, _phase)
          end

          def handle_group_completed(_task_class, _group_name, _phase, _duration)
          end

          def should_activate?
            tty?
          end

          def handle_start
            @output.print "\e[?25l" # Hide cursor
            render_loop { render_tree_live }
          end

          def handle_stop
            stop_render_loop
            @output.print "\e[?25h" # Show cursor
            render_final
          end

          private

          def render_tree_live
            lines = build_tree_lines
            clear_previous_output
            lines.each { |line| @output.puts line }
            @output.flush
            @last_line_count = lines.size
          end

          def render_final
            @monitor.synchronize do
              lines = build_tree_lines
              clear_previous_output

              lines.each { |line| @output.puts line }
              @output.puts render_execution_summary
              @output.flush
            end
          end

          def clear_previous_output
            return if @last_line_count == 0
            # Move cursor up and clear lines
            @output.print "\e[#{@last_line_count}A\e[J"
          end
        end
      end
    end
  end
end
