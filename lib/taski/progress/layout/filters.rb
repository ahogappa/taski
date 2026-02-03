# frozen_string_literal: true

module Taski
  module Progress
    module Layout
      # Liquid filter module for colorizing text output.
      # Uses TemplateDrop from context to get color codes, falls back to defaults.
      #
      # @example Usage in Liquid template
      #   {{ task_name | green }}
      #   {{ error_message | red }}
      #   {{ status | dim }}
      module ColorFilter
        # Default ANSI color codes (used when no template is provided)
        DEFAULT_RED = "\e[31m"
        DEFAULT_GREEN = "\e[32m"
        DEFAULT_YELLOW = "\e[33m"
        DEFAULT_DIM = "\e[2m"
        DEFAULT_RESET = "\e[0m"

        def red(input)
          template = @context["template"]
          color = template&.color_red || DEFAULT_RED
          reset = template&.color_reset || DEFAULT_RESET
          "#{color}#{input}#{reset}"
        end

        def green(input)
          template = @context["template"]
          color = template&.color_green || DEFAULT_GREEN
          reset = template&.color_reset || DEFAULT_RESET
          "#{color}#{input}#{reset}"
        end

        def yellow(input)
          template = @context["template"]
          color = template&.color_yellow || DEFAULT_YELLOW
          reset = template&.color_reset || DEFAULT_RESET
          "#{color}#{input}#{reset}"
        end

        def dim(input)
          template = @context["template"]
          color = template&.color_dim || DEFAULT_DIM
          reset = template&.color_reset || DEFAULT_RESET
          "#{color}#{input}#{reset}"
        end

        # Format a count value using Template's format_count method.
        # Falls back to to_s if no template is provided.
        #
        # @example
        #   {{ done_count | format_count }}
        def format_count(input)
          template = @context["template"]
          template&.format_count(input) || input.to_s
        end

        # Format a duration value using Template's format_duration method.
        # Falls back to default formatting if no template is provided.
        #
        # @example
        #   {{ duration | format_duration }}
        def format_duration(input)
          return "" if input.nil?

          template = @context["template"]
          template&.format_duration(input) || default_format_duration(input)
        end

        # Truncate a list to a maximum number of items, joining with separator.
        # Uses Template's truncate_list_separator and truncate_list_suffix if available.
        #
        # @example
        #   {{ task_names | truncate_list: 3 }}
        #   # => "TaskA, TaskB, TaskC..."
        def truncate_list(input, limit = 3)
          return "" if input.nil?

          items = input.is_a?(Array) ? input : [input]
          return "" if items.empty?

          template = @context["template"]
          separator = template&.truncate_list_separator || ", "
          suffix = template&.truncate_list_suffix || "..."

          truncated = items.first(limit)
          result = truncated.join(separator)
          result += suffix if items.size > limit
          result
        end

        # Truncate text to a maximum length, adding suffix if truncated.
        # Uses Template's truncate_text_suffix if available.
        #
        # @example
        #   {{ output_suffix | truncate_text: 40 }}
        #   # => "Uploading files to server..."
        def truncate_text(input, max_length = 40)
          return "" if input.nil?

          text = input.to_s
          return text if text.length <= max_length

          template = @context["template"]
          suffix = template&.truncate_text_suffix || "..."

          truncated_length = max_length - suffix.length
          text[0, truncated_length] + suffix
        end

        private

        def default_format_duration(ms)
          if ms >= 1000
            "#{(ms / 1000.0).round(1)}s"
          else
            "#{ms}ms"
          end
        end
      end
    end
  end
end
