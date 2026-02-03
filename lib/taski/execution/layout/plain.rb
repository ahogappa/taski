# frozen_string_literal: true

require_relative "base"

module Taski
  module Execution
    module Layout
      # Plain layout for non-TTY environments (CI, log files, piped output).
      # Outputs plain text without terminal escape codes.
      #
      # Output format:
      #   [START] TaskName
      #   [DONE] TaskName (123.4ms)
      #   [FAIL] TaskName: Error message
      #
      # This replaces the old PlainProgressDisplay class.
      class Plain < Base
        def initialize(output: $stderr, template: nil)
          super
          @output.sync = true if @output.respond_to?(:sync=)
        end

        protected

        # === Template method overrides ===

        def on_start
          return unless @root_task_class
          text = render_template(:execution_start, root_task_name: short_name(@root_task_class))
          output_line(text)
        end

        def on_stop
          total_duration = @start_time ? ((Time.now - @start_time) * 1000).to_i : 0
          completed = @tasks.values.count { |t| t.run_state == :completed }
          failed = @tasks.values.count { |t| t.run_state == :failed }
          total = @tasks.size

          text = if failed > 0
            render_template(:execution_fail, failed: failed, total: total, duration: total_duration)
          else
            render_template(:execution_complete, completed: completed, total: total, duration: total_duration)
          end
          output_line(text)
        end

        def on_task_updated(task_class, state, duration, error)
          text = case state
          when :running
            render_template(:task_start, task_name: short_name(task_class))
          when :completed
            render_template(:task_success,
              task_name: short_name(task_class),
              duration: format_duration(duration))
          when :failed
            render_template(:task_fail,
              task_name: short_name(task_class),
              error_message: error&.message)
          when :cleaning
            render_template(:clean_start, task_name: short_name(task_class))
          when :clean_completed
            render_template(:clean_success,
              task_name: short_name(task_class),
              duration: format_duration(duration))
          when :clean_failed
            render_template(:clean_fail,
              task_name: short_name(task_class),
              error_message: error&.message)
          end

          output_line(text) if text
        end

        def on_section_impl_registered(_section_class, impl_class)
          @tasks[impl_class] ||= TaskState.new
        end

        def on_group_updated(task_class, group_name, state, duration, error)
          text = case state
          when :running
            render_template(:group_start,
              task_name: short_name(task_class),
              group_name: group_name)
          when :completed
            render_template(:group_success,
              task_name: short_name(task_class),
              group_name: group_name,
              duration: format_duration(duration))
          when :failed
            render_template(:group_fail,
              task_name: short_name(task_class),
              group_name: group_name,
              error_message: error&.message)
          end

          output_line(text) if text
        end
      end
    end
  end
end
