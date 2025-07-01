# frozen_string_literal: true

require_relative "display_colors"

module Taski
  module Progress
    # Handles formatting of task display messages
    class TaskFormatter
      include DisplayColors

      def format_completed_task(status)
        color = status.success? ? COLORS[:green] : COLORS[:red]
        "#{color}#{COLORS[:bold]}#{status.icon} #{status.name}#{COLORS[:reset]} #{COLORS[:dim]}#{status.format_duration}#{COLORS[:reset]}"
      end

      def format_current_task(spinner_char, task_name)
        "#{COLORS[:cyan]}#{spinner_char}#{COLORS[:reset]} #{COLORS[:bold]}#{task_name}#{COLORS[:reset]}"
      end

      def format_output_line(line)
        "  #{COLORS[:dim]}#{line}#{COLORS[:reset]}"
      end
    end
  end
end
