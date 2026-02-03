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
    end
  end
end
