#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/taski"

# Demo for tree-based progress display with Section
# Run with: TASKI_FORCE_PROGRESS=1 ruby examples/section_progress_demo.rb

# Database Section with multiple impl candidates
class DatabaseSection < Taski::Section
  interfaces :connection_string

  def impl
    if ENV["USE_PROD_DB"] == "1"
      ProductionDB
    else
      DevelopmentDB
    end
  end

  class ProductionDB < Taski::Task
    def run
      puts "Connecting to production database..."
      sleep(0.3)
      @connection_string = "postgresql://prod-server:5432/myapp"
    end
  end

  class DevelopmentDB < Taski::Task
    def run
      puts "Connecting to development database..."
      sleep(0.2)
      @connection_string = "postgresql://localhost:5432/myapp_dev"
    end
  end
end

# Simple task that uses the database
class FetchData < Taski::Task
  exports :data

  def run
    db = DatabaseSection.connection_string
    puts "Fetching data from #{db}..."
    sleep(0.3)
    @data = ["item1", "item2", "item3"]
  end
end

# Main application task
class Application < Taski::Task
  exports :result

  def run
    data = FetchData.data
    puts "Processing #{data.size} items..."
    sleep(0.2)
    @result = "Processed: #{data.join(", ")}"
  end
end

# Show tree structure before execution
puts "Task Tree Structure:"
puts "=" * 60
puts Application.tree
puts "=" * 60
puts

# Reset for execution
Application.reset!

# Execute
result = Application.result

puts "\n"
puts "=" * 60
puts "Execution completed!"
puts "Result: #{result}"
