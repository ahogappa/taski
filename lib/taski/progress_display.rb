# frozen_string_literal: true

require_relative "progress/terminal_controller"
require_relative "progress/spinner_animation"
require_relative "progress/output_capture"
require_relative "progress/display_manager"

module Taski
  # Backward compatibility aliases
  TerminalController = Progress::TerminalController
  SpinnerAnimation = Progress::SpinnerAnimation
  OutputCapture = Progress::OutputCapture
  TaskStatus = Progress::TaskStatus

  # Main progress display controller - refactored for better separation of concerns
  class ProgressDisplay
    def initialize(output: $stdout, enable: true, include_captured_output: nil)
      @output = output
      @terminal = Progress::TerminalController.new(output)
      @spinner = Progress::SpinnerAnimation.new
      @output_capture = Progress::OutputCapture.new(output)

      include_captured_output = include_captured_output.nil? ? (output != $stdout) : include_captured_output
      @display_manager = Progress::DisplayManager.new(@terminal, @spinner, @output_capture, include_captured_output: include_captured_output)

      @enabled = ENV["TASKI_PROGRESS_DISABLE"] != "1" && enable
    end

    def start_task(task_name, dependencies: [])
      return unless @enabled

      @display_manager.start_task_display(task_name)
    end

    def complete_task(task_name, duration:)
      return unless @enabled

      @display_manager.complete_task_display(task_name, duration: duration)
    end

    def fail_task(task_name, error:, duration:)
      return unless @enabled

      @display_manager.fail_task_display(task_name, error: error, duration: duration)
    end

    def clear
      return unless @enabled

      @display_manager.clear_all_displays
    end

    def enabled?
      @enabled
    end
  end
end
