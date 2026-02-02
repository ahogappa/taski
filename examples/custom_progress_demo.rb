#!/usr/bin/env ruby
# frozen_string_literal: true

# Custom Progress Display Demo
#
# This example demonstrates how to create custom progress displays using
# the ProgressFeatures modules and ProgressEventSubscriber.

require_relative "../lib/taski"

puts "=" * 60
puts "Custom Progress Display Demo"
puts "=" * 60
puts

# =============================================================================
# Example 1: Simple Callback-Based Progress (ProgressEventSubscriber)
# =============================================================================
# Use this approach when you want lightweight event handling without
# creating a full display class. Perfect for logging, notifications, or webhooks.

puts "Example 1: ProgressEventSubscriber (Callback-based)"
puts "-" * 60
puts

# Define some sample tasks
module CallbackDemo
  class TaskA < Taski::Task
    exports :result

    def run
      sleep 0.05
      @result = "Task A result"
    end
  end

  class TaskB < Taski::Task
    exports :result

    def run
      _a_result = TaskA.result
      sleep 0.05
      @result = "Task B result"
    end
  end

  class MainTask < Taski::Task
    exports :result

    def run
      _b_result = TaskB.result
      sleep 0.05
      @result = "All done!"
    end
  end
end

# Create a simple logger using ProgressEventSubscriber
logger = Taski::Execution::ProgressEventSubscriber.new do |events|
  events.on_execution_start { puts "  [LOG] Execution started" }
  events.on_execution_stop { puts "  [LOG] Execution completed" }

  events.on_task_start do |task_class, _info|
    puts "  [LOG] Starting: #{task_class.name.split("::").last}"
  end

  events.on_task_complete do |task_class, info|
    duration = info[:duration] ? " (#{info[:duration].round(1)}ms)" : ""
    puts "  [LOG] Completed: #{task_class.name.split("::").last}#{duration}"
  end

  events.on_task_fail do |task_class, info|
    puts "  [LOG] FAILED: #{task_class.name.split("::").last}: #{info[:error]&.message}"
  end

  events.on_progress do |summary|
    percent = (summary[:total] > 0) ? (summary[:completed].to_f / summary[:total] * 100).round(0) : 0
    puts "  [LOG] Progress: #{percent}% (#{summary[:completed]}/#{summary[:total]})"
  end
end

# Disable built-in progress display
ENV["TASKI_PROGRESS_DISABLE"] = "1"
Taski.reset_progress_display!

# Add our logger as an observer to ExecutionContext
# This is the key integration point
context = Taski::Execution::ExecutionContext.new
context.add_observer(logger)

# Run with our custom context
old_context = Taski::Execution::ExecutionContext.current
begin
  Taski::Execution::ExecutionContext.current = context
  CallbackDemo::MainTask.run
ensure
  Taski::Execution::ExecutionContext.current = old_context
end

puts
puts "=" * 60
puts "Example 2: Custom Progress Display with ProgressFeatures"
puts "=" * 60
puts

# =============================================================================
# Example 2: Custom Progress Display Using ProgressFeatures Modules
# =============================================================================
# Use this approach when you need full control over the display format.
# Mix in the modules you need and implement your own rendering logic.

class MinimalProgressDisplay
  include Taski::Execution::ProgressFeatures::SpinnerAnimation
  include Taski::Execution::ProgressFeatures::TerminalControl
  include Taski::Execution::ProgressFeatures::Formatting
  include Taski::Execution::ProgressFeatures::ProgressTracking

  def initialize(output: $stdout)
    @output = output
    init_progress_tracking
    @running = false
  end

  def set_root_task(task_class)
    @root_task_class = task_class
  end

  def set_output_capture(capture)
    @output_capture = capture
  end

  def register_section_impl(section_class, impl_class)
    register_task(impl_class)
  end

  def register_task(task_class)
    super
  end

  def update_task(task_class, state:, duration: nil, error: nil)
    register_task(task_class)
    update_task_state(task_class, state, duration, error)
  end

  def update_group(task_class, group_name, state:, duration: nil, error: nil)
    # Simplified: just track the state
  end

  def task_registered?(task_class)
    @tracked_tasks&.key?(task_class) || false
  end

  def queue_message(text)
    @messages ||= []
    @messages << text
  end

  def start
    @running = true
    if tty?
      hide_cursor
      # Use custom spinner frames
      start_spinner(frames: %w[. .. ... ....], interval: 0.2) { render }
    end
  end

  def stop
    if tty?
      stop_spinner
      show_cursor
    end
    @running = false
    render_final
    flush_messages
  end

  private

  def render
    summary = progress_summary
    status = summary[:failed].any? ? "X" : current_frame
    running_name = summary[:running].first ? " #{short_name(summary[:running].first)}" : ""

    line = "[#{status}] #{summary[:completed]}/#{summary[:total]}#{running_name}"
    clear_line
    @output.print line
    @output.flush
  end

  def render_final
    clear_line
    summary = progress_summary
    if summary[:failed].any?
      @output.puts "Failed: #{summary[:failed].map { |t| short_name(t) }.join(", ")}"
    else
      @output.puts "Completed: #{summary[:completed]}/#{summary[:total]} tasks"
    end
  end

  def flush_messages
    @messages&.each { |msg| @output.puts msg }
  end
end

# Reset tasks for second demo
CallbackDemo::TaskA.reset!
CallbackDemo::TaskB.reset!
CallbackDemo::MainTask.reset!

# Create and use our custom display
display = MinimalProgressDisplay.new

context2 = Taski::Execution::ExecutionContext.new
context2.add_observer(display)

puts "Running with MinimalProgressDisplay:"

old_context2 = Taski::Execution::ExecutionContext.current
begin
  Taski::Execution::ExecutionContext.current = context2
  CallbackDemo::MainTask.run
ensure
  Taski::Execution::ExecutionContext.current = old_context2
end

ENV.delete("TASKI_PROGRESS_DISABLE")
Taski.reset_progress_display!

puts
puts "=" * 60
puts "Demo complete!"
puts "=" * 60
