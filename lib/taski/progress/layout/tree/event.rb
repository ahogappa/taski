# frozen_string_literal: true

require_relative "../base"
require_relative "../../theme/detail"
require_relative "structure"

module Taski
  module Progress
    module Layout
      module Tree
        # Non-TTY event-driven tree layout.
        # Outputs lines immediately with tree prefixes as events arrive.
        # Used for logs, CI, piped output, and static tree display.
        class Event < Base
          include Structure

          def initialize(output: $stderr, theme: nil)
            theme ||= Theme::Detail.new
            super
            init_tree_structure
          end

          protected

          def handle_ready
            build_ready_tree
          end

          def handle_task_update(task_class, current_state, phase)
            progress = @tasks[task_class]
            duration = compute_duration(progress, phase)
            text = render_for_task_event(task_class, current_state, duration, nil, phase)
            output_with_prefix(task_class, text) if text
          end

          def handle_group_started(task_class, group_name, phase)
            text = render_group_started(task_class, group_name: group_name)
            output_with_prefix(task_class, text) if text
          end

          def handle_group_completed(task_class, group_name, phase, duration)
            text = render_group_succeeded(task_class, group_name: group_name, task_duration: duration)
            output_with_prefix(task_class, text) if text
          end
        end
      end
    end
  end
end
