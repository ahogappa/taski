#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/taski"

# Demo task that outputs text during execution
# Used to test output capture and display feature

class TaskWithOutput < Taski::Task
  exports :result

  def run
    puts "Starting work..."
    sleep 0.5
    puts "Processing step 1..."
    sleep 0.5
    puts "Processing step 2..."
    sleep 0.5
    puts "Finished!"
    @result = "done"
  end
end

class MainTask < Taski::Task
  exports :final

  def run
    data = TaskWithOutput.result
    puts "Main task starting..."
    sleep 0.3
    puts "Main task finishing..."
    @final = "completed: #{data}"
  end
end

Taski.progress_display&.start
result = MainTask.final
Taski.progress_display&.stop
puts "\nResult: #{result}"
