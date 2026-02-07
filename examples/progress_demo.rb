#!/usr/bin/env ruby
# frozen_string_literal: true

# Taski Progress Display Demo
#
# This example demonstrates the progress display modes:
# - Simple mode (default): One-line spinner with current task name
# - Tree mode: Shows task hierarchy with real-time updates
#
# Run:
#   ruby examples/progress_demo.rb              # Simple mode (default)
#
# Covers:
# - Parallel task execution with progress display
# - Tree vs simple progress modes
# - Task output capture and display
# - system() output streaming

require_relative "../lib/taski"

# Configuration task with conditional logic
class DatabaseConfig < Taski::Task
  exports :connection_string

  def run
    if ENV["USE_PROD_DB"] == "1"
      puts "Connecting to production database..."
      sleep(0.4)
      @connection_string = "postgresql://prod-server:5432/myapp"
    else
      puts "Connecting to development database..."
      sleep(0.3)
      @connection_string = "postgresql://localhost:5432/myapp_dev"
    end
  end
end

# Parallel download tasks (executed concurrently)
class DownloadLayer1 < Taski::Task
  exports :layer1_data

  def run
    puts "Downloading base image..."
    sleep(0.8)
    puts "Base image complete"
    @layer1_data = "Layer 1 (base)"
  end
end

class DownloadLayer2 < Taski::Task
  exports :layer2_data

  def run
    puts "Downloading dependencies..."
    sleep(1.2)
    puts "Dependencies complete"
    @layer2_data = "Layer 2 (deps)"
  end
end

class DownloadLayer3 < Taski::Task
  exports :layer3_data

  def run
    puts "Downloading application..."
    sleep(0.4)
    puts "Application complete"
    @layer3_data = "Layer 3 (app)"
  end
end

# Task that depends on all downloads (waits for parallel completion)
class ExtractLayers < Taski::Task
  exports :extracted_data

  def run
    layer1 = DownloadLayer1.layer1_data
    layer2 = DownloadLayer2.layer2_data
    layer3 = DownloadLayer3.layer3_data

    puts "Extracting layers..."
    sleep(0.3)
    @extracted_data = [layer1, layer2, layer3]
  end
end

# Task demonstrating system() output capture
class RunSystemCommand < Taski::Task
  exports :command_result

  def run
    puts "Running system command..."
    @command_result = system("echo 'Step 1: Preparing...' && sleep 0.2 && echo 'Step 2: Processing...' && sleep 0.2 && echo 'Step 3: Done'")
  end
end

# Final task combining all dependencies
class BuildApplication < Taski::Task
  exports :result

  def run
    db = DatabaseConfig.connection_string
    layers = ExtractLayers.extracted_data
    RunSystemCommand.command_result

    puts "Building application..."
    sleep(0.3)
    puts "Finalizing build..."
    sleep(0.2)

    @result = {
      database: db,
      layers: layers,
      status: "success"
    }
  end
end

# Main execution
puts "Taski Progress Display Demo"
puts "=" * 50
puts "Progress display: #{Taski.progress_display.class}"
puts

puts "Task Tree Structure:"
puts "-" * 50
puts BuildApplication.tree
puts "-" * 50
puts

# Reset for fresh execution
BuildApplication.reset!

# Execute (progress display is automatic)
result = BuildApplication.result

puts
puts "=" * 50
puts "Execution completed!"
puts "Result: #{result.inspect}"
puts
puts "To use tree mode, add before execution:"
puts "  Taski.progress_display = Taski::Progress::Layout::Tree.new"
