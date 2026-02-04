# frozen_string_literal: true

require_relative "default"

module Taski
  module Progress
    module Template
      # Tree template for TTY environments with tree-structured progress display.
      # Provides spinner animation, colored icons for task states.
      #
      # Output format:
      #   ├── ⠹ DeployTask
      #   │   └── ✓ UploadFiles (1.2s)
      #   └── ✗ MigrateDB: Connection refused
      #
      # @example Usage
      #   layout = Taski::Progress::Layout::Tree.new(
      #     template: Taski::Progress::Template::Tree.new
      #   )
      class Tree < Default
        # Task pending with icon
        def task_pending
          "{% icon %} {{ task_name }}"
        end

        # Task start with spinner
        def task_start
          "{% spinner %} {{ task_name }}"
        end

        # Task success with colored icon
        def task_success
          "{% icon %} {{ task_name }}{% if duration %} ({{ duration | format_duration }}){% endif %}"
        end

        # Task fail with colored icon
        def task_fail
          "{% icon %} {{ task_name }}{% if task_error_message %}: {{ task_error_message }}{% endif %}"
        end
      end
    end
  end
end
