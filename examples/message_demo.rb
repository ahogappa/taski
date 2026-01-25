#!/usr/bin/env ruby
# frozen_string_literal: true

# Demonstrates Taski.message API
#
# Taski.message outputs text to the user without being captured by TaskOutputRouter.
# Messages are queued during progress display and shown after task completion.
#
# Usage:
#   ruby examples/message_demo.rb
#   TASKI_FORCE_PROGRESS=1 ruby examples/message_demo.rb  # Force progress display

require_relative "../lib/taski"

class ProcessDataTask < Taski::Task
  exports :processed_count

  def run
    puts "Starting data processing..."  # Captured by TaskOutputRouter

    # Simulate processing
    5.times do |i|
      puts "Processing batch #{i + 1}/5..."  # Captured
      sleep 0.3
    end

    @processed_count = 42

    # These messages bypass TaskOutputRouter and appear after execution
    Taski.message("Created: /tmp/output.txt")
    Taski.message("Summary: #{@processed_count} items processed successfully")
  end
end

class GenerateReportTask < Taski::Task
  exports :report_path

  def run
    # Dependency: ProcessDataTask will be executed first
    count = ProcessDataTask.processed_count
    puts "Generating report for #{count} items..."  # Captured

    sleep 0.5

    @report_path = "/tmp/report.pdf"

    Taski.message("Report available at: #{@report_path}")
  end
end

puts "=== Taski.message Demo ==="
puts

GenerateReportTask.run

puts
puts "=== Done ==="
