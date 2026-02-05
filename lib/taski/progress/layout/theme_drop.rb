# frozen_string_literal: true

require "liquid"

module Taski
  module Progress
    module Layout
      # Liquid Drop for Theme to enable method access from filters/tags.
      # Wraps a Theme instance and delegates color/icon/spinner methods.
      #
      # @example Using in Liquid context
      #   drop = ThemeDrop.new(theme)
      #   Liquid::Template.parse("{{ theme.color_red }}")
      #                   .render("theme" => drop)
      class ThemeDrop < Liquid::Drop
        def initialize(theme)
          @theme = theme
        end

        # Color methods
        def color_red = @theme.color_red
        def color_green = @theme.color_green
        def color_yellow = @theme.color_yellow
        def color_dim = @theme.color_dim
        def color_reset = @theme.color_reset

        # Spinner settings
        def spinner_frames = @theme.spinner_frames
        def spinner_interval = @theme.spinner_interval
        def render_interval = @theme.render_interval

        # Status icons
        def icon_success = @theme.icon_success
        def icon_failure = @theme.icon_failure
        def icon_pending = @theme.icon_pending
        def icon_skipped = @theme.icon_skipped

        # Formatting methods (used by filters)
        def format_count(count) = @theme.format_count(count)
        def format_duration(ms) = @theme.format_duration(ms)

        # List truncation settings
        def truncate_list_separator = @theme.truncate_list_separator
        def truncate_list_suffix = @theme.truncate_list_suffix

        # Text truncation settings
        def truncate_text_suffix = @theme.truncate_text_suffix
      end

      # Base class for Liquid Drops with dynamic property access.
      # Provides common functionality for TaskDrop and ExecutionDrop.
      class DataDrop < Liquid::Drop
        def initialize(**data)
          @data = data
        end

        def liquid_method_missing(method)
          @data[method.to_sym]
        end
      end

      # Liquid Drop for task-specific variables.
      # Provides access to individual task information in templates.
      #
      # Available properties: name, state, duration, error_message, group_name, stdout
      #
      # @example Using in Liquid template
      #   {{ task.name }} ({{ task.state }})
      #   {{ task.duration | format_duration }}
      class TaskDrop < DataDrop; end

      # Liquid Drop for execution-level variables.
      # Provides access to overall execution state in templates.
      #
      # Available properties: state, pending_count, done_count, completed_count,
      #   failed_count, total_count, total_duration, root_task_name, task_names
      #
      # @example Using in Liquid template
      #   [{{ execution.completed_count }}/{{ execution.total_count }}]
      #   {{ execution.total_duration | format_duration }}
      class ExecutionDrop < DataDrop; end
    end
  end
end
