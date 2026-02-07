# frozen_string_literal: true

module Taski
  module Progress
    module Layout
      # Liquid filter module for colorizing text output.
      # Uses TemplateDrop from context to get color codes, falls back to defaults.
      #
      # @example Usage in Liquid template
      #   {{ task.name | green }}
      #   {{ task.error_message | red }}
      #   {{ task.state | dim }}
      module ColorFilter
        DEFAULT_COLORS = {
          red: "\e[31m",
          green: "\e[32m",
          yellow: "\e[33m",
          dim: "\e[2m",
          reset: "\e[0m"
        }.freeze

        def red(input) = colorize(input, :red)
        def green(input) = colorize(input, :green)
        def yellow(input) = colorize(input, :yellow)
        def dim(input) = colorize(input, :dim)

        # Format a count value using Theme's format_count method.
        # Falls back to to_s if no template is provided.
        #
        # @example
        #   {{ execution.done_count | format_count }}
        def format_count(input)
          template = @context["template"]
          template&.format_count(input) || input.to_s
        end

        # Format a duration value using Theme's format_duration method.
        # Falls back to default formatting if no template is provided.
        #
        # @example
        #   {{ task.duration | format_duration }}
        #   {{ execution.total_duration | format_duration }}
        def format_duration(input)
          return "" if input.nil?

          template = @context["template"]
          template&.format_duration(input) || default_format_duration(input)
        end

        # Truncate a list to a maximum number of items, joining with separator.
        # Uses Theme's truncate_list_separator and truncate_list_suffix if available.
        #
        # @example
        #   {{ execution.task_names | truncate_list: 3 }}
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

        # Extract short name from a fully qualified class name.
        # Returns the last component after "::".
        #
        # @example
        #   {{ task.name | short_name }}
        #   # "MyModule::MyTask" => "MyTask"
        def short_name(input)
          return "" if input.nil?
          input.to_s.split("::").last || input.to_s
        end

        # Truncate text to a maximum length, adding suffix if truncated.
        # Uses Theme's truncate_text_suffix if available.
        #
        # @example
        #   {{ task.stdout | truncate_text: 40 }}
        #   # => "Uploading files to server..."
        def truncate_text(input, max_length = 40)
          return "" if input.nil?
          return "" if max_length <= 0

          text = input.to_s
          return text if text.length <= max_length

          template = @context["template"]
          suffix = template&.truncate_text_suffix || "..."

          truncated_length = [max_length - suffix.length, 0].max
          if truncated_length == 0
            suffix[0, max_length]
          else
            text[0, truncated_length] + suffix
          end
        end

        private

        def colorize(input, color_name)
          template = @context["template"]
          color = template&.public_send(:"color_#{color_name}") || DEFAULT_COLORS[color_name]
          reset = template&.color_reset || DEFAULT_COLORS[:reset]
          "#{color}#{input}#{reset}"
        end

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
