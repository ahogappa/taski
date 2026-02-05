#!/usr/bin/env ruby
# frozen_string_literal: true

# Taski Args & Env API Example
#
# This example demonstrates the Args and Env APIs:
# - Taski.env: Execution environment information
#   - working_directory: Where execution started
#   - started_at: When execution began
#   - root_task: The first task class that was called
# - Taski.args: User-defined options passed via run(args: {...})
#
# Run: ruby examples/args_demo.rb

require_relative "../lib/taski"

puts "Taski Args & Env API Example"
puts "=" * 40

# Task that uses env information for logging
class SetupTask < Taski::Task
  exports :setup_info

  def run
    puts "Setup running..."
    puts "  Working directory: #{Taski.env.working_directory}"
    puts "  Started at: #{Taski.env.started_at}"
    puts "  Root task: #{Taski.env.root_task}"
    puts "  Environment: #{Taski.args[:env]}"

    @setup_info = {
      directory: Taski.env.working_directory,
      timestamp: Taski.env.started_at,
      env: Taski.args[:env]
    }
  end
end

# Task that creates files relative to working directory
class FileProcessor < Taski::Task
  exports :output_path

  def run
    # Use env to determine output location
    base_dir = Taski.env.working_directory
    env = Taski.args.fetch(:env, "development")
    @output_path = File.join(base_dir, "tmp", env, "output.txt")

    puts "FileProcessor: Would write to #{@output_path}"
    puts "  (relative to working directory, env: #{env})"
  end
end

# Task that logs execution timing
class TimingTask < Taski::Task
  exports :duration_info

  def run
    start_time = Taski.env.started_at
    current_time = Time.now
    elapsed = current_time - start_time

    puts "TimingTask: #{elapsed.round(3)}s since execution started"
    puts "  Debug mode: #{Taski.args.fetch(:debug, false)}"

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
    puts "  Root task is: #{Taski.env.root_task}"
    puts "  Environment: #{Taski.args[:env]}"

    # Access dependencies
    setup = SetupTask.setup_info
    output = FileProcessor.output_path
    timing = TimingTask.duration_info

    @summary = {
      setup: setup,
      output_path: output,
      timing: timing,
      root_task: Taski.env.root_task.to_s
    }

    puts "\nExecution Summary:"
    puts "  Setup directory: #{setup[:directory]}"
    puts "  Output path: #{output}"
    puts "  Total elapsed: #{timing[:elapsed_seconds].round(3)}s"
  end
end

puts "\n1. Running MainTask with args options"
puts "-" * 40
MainTask.run(args: {env: "production", debug: true})

puts "\n" + "=" * 40
puts "\n2. Running SetupTask directly with different args"
puts "-" * 40
SetupTask.reset!
SetupTask.run(args: {env: "staging"})

puts "\n" + "=" * 40
puts "\n3. Dependency Tree"
puts "-" * 40
puts MainTask.tree

puts "\n" + "=" * 40
puts "Args & Env API demonstration complete!"
puts "Note: Args provides user options, Env provides execution environment info."
