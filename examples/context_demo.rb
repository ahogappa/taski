#!/usr/bin/env ruby
# frozen_string_literal: true

# Taski Context API Example
#
# This example demonstrates the Context API for accessing runtime information:
# - working_directory: Where execution started
# - started_at: When execution began
# - root_task: The first task class that was called
#
# Run: ruby examples/context_demo.rb

require_relative "../lib/taski"

puts "Taski Context API Example"
puts "=" * 40

# Task that uses context information for logging
class SetupTask < Taski::Task
  exports :setup_info

  def run
    puts "Setup running..."
    puts "  Working directory: #{Taski::Context.working_directory}"
    puts "  Started at: #{Taski::Context.started_at}"
    puts "  Root task: #{Taski::Context.root_task}"

    @setup_info = {
      directory: Taski::Context.working_directory,
      timestamp: Taski::Context.started_at
    }
  end
end

# Task that creates files relative to working directory
class FileProcessor < Taski::Task
  exports :output_path

  def run
    # Use context to determine output location
    base_dir = Taski::Context.working_directory
    @output_path = File.join(base_dir, "tmp", "output.txt")

    puts "FileProcessor: Would write to #{@output_path}"
    puts "  (relative to working directory)"
  end
end

# Task that logs execution timing
class TimingTask < Taski::Task
  exports :duration_info

  def run
    start_time = Taski::Context.started_at
    current_time = Time.now
    elapsed = current_time - start_time

    puts "TimingTask: #{elapsed.round(3)}s since execution started"

    @duration_info = {
      started: start_time,
      current: current_time,
      elapsed_seconds: elapsed
    }
  end
end

# Main task that depends on others
class MainTask < Taski::Task
  exports :summary

  def run
    puts "\nMainTask executing..."
    puts "  Root task is: #{Taski::Context.root_task}"

    # Access dependencies
    setup = SetupTask.setup_info
    output = FileProcessor.output_path
    timing = TimingTask.duration_info

    @summary = {
      setup: setup,
      output_path: output,
      timing: timing,
      root_task: Taski::Context.root_task.to_s
    }

    puts "\nExecution Summary:"
    puts "  Setup directory: #{setup[:directory]}"
    puts "  Output path: #{output}"
    puts "  Total elapsed: #{timing[:elapsed_seconds].round(3)}s"
  end
end

puts "\n1. Running MainTask (context will show MainTask as root)"
puts "-" * 40
MainTask.run

puts "\n" + "=" * 40
puts "\n2. Running SetupTask directly (context will show SetupTask as root)"
puts "-" * 40
SetupTask.reset!
SetupTask.run

puts "\n" + "=" * 40
puts "\n3. Dependency Tree"
puts "-" * 40
puts MainTask.tree

puts "\n" + "=" * 40
puts "Context API demonstration complete!"
puts "Note: Context provides runtime information without affecting dependency analysis."
