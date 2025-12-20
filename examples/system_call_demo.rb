#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/taski"

# Demo: Subprocess output capture with system()
#
# This example demonstrates how Taski captures output from system() calls
# and displays them in the progress spinner.
# Run with: TASKI_FORCE_PROGRESS=1 ruby examples/system_call_demo.rb

class SlowOutputTask < Taski::Task
  exports :success

  def run
    puts "Running command with streaming output..."
    # Use a command that produces output over time
    @success = system("for i in 1 2 3 4 5; do echo \"Processing step $i...\"; sleep 0.3; done")
  end
end

class AnotherSlowTask < Taski::Task
  exports :result

  def run
    puts "Running another slow command..."
    @result = system("for i in A B C; do echo \"Stage $i complete\"; sleep 0.4; done")
  end
end

class MainTask < Taski::Task
  exports :summary

  def run
    puts "Starting main task..."
    slow1 = SlowOutputTask.success
    slow2 = AnotherSlowTask.result
    @summary = {slow1: slow1, slow2: slow2}
    puts "All done!"
  end
end

puts "=" * 60
puts "Subprocess Output Capture Demo"
puts "Watch the spinner show system() output in real-time!"
puts "=" * 60
puts

Taski.progress_display&.start
result = MainTask.summary
Taski.progress_display&.stop

puts
puts "=" * 60
puts "Result: #{result.inspect}"
puts "=" * 60
