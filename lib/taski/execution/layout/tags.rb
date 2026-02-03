# frozen_string_literal: true

require "liquid"

module Taski
  module Execution
    module Layout
      # Liquid tag for rendering animated spinner characters.
      # Uses TemplateDrop from context to get spinner frames, falls back to defaults.
      # Uses spinner_index from context to determine current frame.
      #
      # @example Usage in Liquid template
      #   {% spinner %} Loading...
      #   {% spinner %} [{{ done }}/{{ total }}]
      class SpinnerTag < Liquid::Tag
        DEFAULT_FRAMES = %w[⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏].freeze

        def render(context)
          template = context["template"]
          frames = template&.spinner_frames || DEFAULT_FRAMES
          index = context["spinner_index"] || 0
          frames[index % frames.size]
        end
      end

      # Liquid tag for rendering status icons based on current state.
      # Uses TemplateDrop from context to get icons and colors.
      # Uses state from context to determine which icon to show.
      #
      # @example Usage in Liquid template
      #   {% icon %} Task completed
      #   {% icon %} [{{ done }}/{{ total }}]
      class IconTag < Liquid::Tag
        # Default icons (used when no template is provided)
        DEFAULT_ICON_SUCCESS = "✓"
        DEFAULT_ICON_FAILURE = "✗"
        DEFAULT_ICON_PENDING = "○"

        # Default colors
        DEFAULT_COLOR_GREEN = "\e[32m"
        DEFAULT_COLOR_RED = "\e[31m"
        DEFAULT_COLOR_YELLOW = "\e[33m"
        DEFAULT_COLOR_RESET = "\e[0m"

        def render(context)
          template = context["template"]
          state = context["state"]&.to_s

          case state
          when "completed", "clean_completed"
            icon = template&.icon_success || DEFAULT_ICON_SUCCESS
            color = template&.color_green || DEFAULT_COLOR_GREEN
            reset = template&.color_reset || DEFAULT_COLOR_RESET
            "#{color}#{icon}#{reset}"
          when "failed", "clean_failed"
            icon = template&.icon_failure || DEFAULT_ICON_FAILURE
            color = template&.color_red || DEFAULT_COLOR_RED
            reset = template&.color_reset || DEFAULT_COLOR_RESET
            "#{color}#{icon}#{reset}"
          when "running", "cleaning"
            icon = template&.icon_pending || DEFAULT_ICON_PENDING
            color = template&.color_yellow || DEFAULT_COLOR_YELLOW
            reset = template&.color_reset || DEFAULT_COLOR_RESET
            "#{color}#{icon}#{reset}"
          else
            # pending or unknown state - no color
            template&.icon_pending || DEFAULT_ICON_PENDING
          end
        end
      end
    end
  end
end
