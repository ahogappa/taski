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
      #   Taski.progress.layout = Taski::Progress::Layout::Tree
      #   Taski.progress.theme = Taski::Progress::Theme::Detail
      class Detail < Default
        # Task pending with icon
        def task_pending(task:, execution: nil) = "#{icon_for(task.state)} #{short_name(task.name)}"

        # Task start with spinner
        def task_start(task:, execution: nil) = "#{spinner_frame(execution&.spinner_index)} #{short_name(task.name)}"

        # Task success with colored icon
        def task_success(task:, execution: nil) = "#{icon_for(task.state)} #{short_name(task.name)}#{duration_part(task.duration)}"

        # Task fail with colored icon
        def task_fail(task:, execution: nil) = "#{icon_for(task.state)} #{short_name(task.name)}#{error_part(task.error_message)}"

        # Task skip with colored icon
        def task_skip(task:, execution: nil) = "#{icon_for(task.state)} #{short_name(task.name)}"
      end
    end
  end
end
