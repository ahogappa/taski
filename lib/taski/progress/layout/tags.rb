# frozen_string_literal: true

require "liquid"
require_relative "filters"

module Taski
  module Progress
    module Layout
      # Liquid tag for rendering animated spinner characters.
      # Uses ThemeDrop from context to get spinner frames, falls back to defaults.
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
      # Uses ThemeDrop from context to get icons and colors.
      # Uses state from context to determine which icon to show.
      #
      # @example Usage in Liquid template
      #   {% icon %} Task completed
      #   {% icon %} [{{ done }}/{{ total }}]
      class IconTag < Liquid::Tag
        DEFAULTS = {
          icon_success: "✓",
          icon_failure: "✗",
          icon_pending: "○",
          icon_skip: "⊘",
          color_green: ColorFilter::DEFAULT_COLORS[:green],
          color_red: ColorFilter::DEFAULT_COLORS[:red],
          color_yellow: ColorFilter::DEFAULT_COLORS[:yellow],
          color_dim: ColorFilter::DEFAULT_COLORS[:dim],
          color_reset: ColorFilter::DEFAULT_COLORS[:reset]
        }.freeze

        STATE_CONFIG = {
          "completed" => {icon: :icon_success, color: :color_green},
          "failed" => {icon: :icon_failure, color: :color_red},
          "running" => {icon: :icon_pending, color: :color_yellow},
          "skipped" => {icon: :icon_skip, color: :color_dim}
        }.freeze

        def render(context)
          @template = context["template"]
          state = context["state"]&.to_s

          config = STATE_CONFIG[state]
          return get_value(:icon_pending) unless config

          colorize(get_value(config[:icon]), config[:color])
        end

        private

        def get_value(key)
          @template&.public_send(key) || DEFAULTS[key]
        end

        def colorize(icon, color_key)
          "#{get_value(color_key)}#{icon}#{get_value(:color_reset)}"
        end
      end
    end
  end
end
