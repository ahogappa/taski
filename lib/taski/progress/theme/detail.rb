# frozen_string_literal: true

require_relative "default"

module Taski
  module Progress
    module Theme
      # Detail theme for rich progress display with spinner and icons.
      # Provides spinner animation, colored icons for task states.
      #
      # Output format:
      #   ├── ⠹ DeployTask
      #   │   └── ✓ UploadFiles (1.2s)
      #   └── ✗ MigrateDB: Connection refused
      #
      # @example Usage
      #   layout = Taski::Progress::Layout::Tree.new(
      #     theme: Taski::Progress::Theme::Detail.new
      #   )
      class Detail < Default
        # Task pending with icon
        def task_pending
          "{% icon %} {{ task.name | short_name }}"
        end

        # Task start with spinner
        def task_start
          "{% spinner %} {{ task.name | short_name }}"
        end

        # Task success with colored icon
        def task_success
          "{% icon %} {{ task.name | short_name }}{% if task.duration %} ({{ task.duration | format_duration }}){% endif %}"
        end

        # Task fail with colored icon
        def task_fail
          "{% icon %} {{ task.name | short_name }}{% if task.error_message %}: {{ task.error_message }}{% endif %}"
        end
      end
    end
  end
end
