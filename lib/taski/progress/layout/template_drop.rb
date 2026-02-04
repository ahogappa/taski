# frozen_string_literal: true

require "liquid"

module Taski
  module Progress
    module Layout
      # Liquid Drop for Template to enable method access from filters/tags.
      # Wraps a Template instance and delegates color/icon/spinner methods.
      #
      # @example Using in Liquid context
      #   drop = TemplateDrop.new(template)
      #   Liquid::Template.parse("{{ template.color_red }}")
      #                   .render("template" => drop)
      class TemplateDrop < Liquid::Drop
        def initialize(template)
          @template = template
        end

        # Color methods
        def color_red = @template.color_red
        def color_green = @template.color_green
        def color_yellow = @template.color_yellow
        def color_dim = @template.color_dim
        def color_reset = @template.color_reset

        # Spinner settings
        def spinner_frames = @template.spinner_frames
        def spinner_interval = @template.spinner_interval
        def render_interval = @template.render_interval

        # Status icons
        def icon_success = @template.icon_success
        def icon_failure = @template.icon_failure
        def icon_pending = @template.icon_pending

        # Formatting methods (used by filters)
        def format_count(count) = @template.format_count(count)
        def format_duration(ms) = @template.format_duration(ms)

        # List truncation settings
        def truncate_list_separator = @template.truncate_list_separator
        def truncate_list_suffix = @template.truncate_list_suffix

        # Text truncation settings
        def truncate_text_suffix = @template.truncate_text_suffix
      end

      # Liquid Drop for task-specific variables.
      # Provides access to individual task information in templates.
      #
      # @example Using in Liquid template
      #   {{ task.name }} ({{ task.state }})
      #   {{ task.duration | format_duration }}
      class TaskDrop < Liquid::Drop
        attr_reader :name, :state, :duration, :error_message, :group_name, :stdout

        def initialize(name: nil, state: nil, duration: nil, error_message: nil, group_name: nil, stdout: nil)
          @name = name
          @state = state
          @duration = duration
          @error_message = error_message
          @group_name = group_name
          @stdout = stdout
        end
      end

      # Liquid Drop for execution-level variables.
      # Provides access to overall execution state in templates.
      #
      # @example Using in Liquid template
      #   [{{ execution.completed_count }}/{{ execution.total_count }}]
      #   {{ execution.total_duration | format_duration }}
      class ExecutionDrop < Liquid::Drop
        attr_reader :state, :pending_count, :done_count, :completed_count,
          :failed_count, :total_count, :total_duration, :root_task_name, :task_names

        def initialize(
          state: nil,
          pending_count: nil,
          done_count: nil,
          completed_count: nil,
          failed_count: nil,
          total_count: nil,
          total_duration: nil,
          root_task_name: nil,
          task_names: nil
        )
          @state = state
          @pending_count = pending_count
          @done_count = done_count
          @completed_count = completed_count
          @failed_count = failed_count
          @total_count = total_count
          @total_duration = total_duration
          @root_task_name = root_task_name
          @task_names = task_names
        end
      end
    end
  end
end
