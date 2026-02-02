# frozen_string_literal: true

require_relative "progress_features/spinner_animation"
require_relative "progress_features/terminal_control"
require_relative "progress_features/ansi_colors"
require_relative "progress_features/formatting"
require_relative "progress_features/tree_rendering"
require_relative "progress_features/progress_tracking"

module Taski
  module Execution
    # ProgressFeatures provides reusable modules for building custom progress displays.
    #
    # These modules can be mixed into custom display classes to provide common
    # functionality like spinner animations, terminal control, ANSI colors,
    # text formatting, tree rendering, and progress tracking.
    #
    # @example Building a custom progress display
    #   class MyProgressDisplay
    #     include Taski::Execution::ProgressFeatures::SpinnerAnimation
    #     include Taski::Execution::ProgressFeatures::TerminalControl
    #     include Taski::Execution::ProgressFeatures::Formatting
    #     include Taski::Execution::ProgressFeatures::ProgressTracking
    #
    #     def initialize(output: $stdout)
    #       @output = output
    #       init_progress_tracking
    #     end
    #
    #     def start
    #       hide_cursor
    #       start_spinner { render }
    #     end
    #
    #     def stop
    #       stop_spinner
    #       show_cursor
    #     end
    #
    #     def update_task(task_class, state:, duration: nil, error: nil)
    #       register_task(task_class)
    #       update_task_state(task_class, state, duration, error)
    #     end
    #
    #     private
    #
    #     def render
    #       summary = progress_summary
    #       @output.print "\r#{current_frame} [#{summary[:completed]}/#{summary[:total]}]"
    #     end
    #   end
    module ProgressFeatures
    end
  end
end
