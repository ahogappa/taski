#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/taski"

# Demo for nested Sections (Section inside Section)
# Run with: ruby examples/nested_section_demo.rb

# Configuration loader task - determines which storage to use
class StorageConfig < Taski::Task
  exports :use_s3

  def run
    puts "Loading storage configuration..."
    sleep(0.4)
    puts "Checking cloud credentials..."
    sleep(0.3)
    puts "Validating storage policies..."
    sleep(0.3)
    # Simulate config loading - use local storage by default
    @use_s3 = ENV["USE_S3"] == "1"
  end
end

# Inner Section: Storage backend selection (depends on StorageConfig)
class StorageSection < Taski::Section
  interfaces :storage_client

  def impl
    # Use config task result to decide implementation
    if StorageConfig.use_s3
      S3Storage
    else
      LocalStorage
    end
  end

  class S3Storage < Taski::Task
    def run
      puts "Connecting to S3..."
      sleep(1.0)
      @storage_client = "s3://bucket/data"
    end
  end

  class LocalStorage < Taski::Task
    def run
      puts "Initializing local filesystem..."
      sleep(0.5)
      puts "Mounting volumes..."
      sleep(0.5)
      puts "Local storage ready"
      sleep(0.3)
      @storage_client = "/var/data"
    end
  end
end

# Database configuration loader - determines which database to use
class DatabaseConfig < Taski::Task
  exports :use_prod

  def run
    puts "Loading database configuration..."
    sleep(0.3)
    puts "Checking environment variables..."
    sleep(0.3)
    puts "Resolving database endpoints..."
    sleep(0.4)
    # Simulate config loading - use dev database by default
    @use_prod = ENV["USE_PROD_DB"] == "1"
  end
end

# Outer Section: Database selection (depends on Storage and DatabaseConfig)
class DatabaseSection < Taski::Section
  interfaces :connection_string

  def impl
    # Use config task result to decide implementation
    if DatabaseConfig.use_prod
      ProductionDB
    else
      DevelopmentDB
    end
  end

  class ProductionDB < Taski::Task
    def run
      # Production DB also needs storage for backups
      storage = StorageSection.storage_client
      puts "Connecting to production database (backup: #{storage})..."
      sleep(0.8)
      @connection_string = "postgresql://prod-server:5432/myapp"
    end
  end

  class DevelopmentDB < Taski::Task
    def run
      # Dev DB uses storage for test data
      storage = StorageSection.storage_client
      puts "Initializing dev database connection..."
      sleep(0.4)
      puts "Loading test fixtures from #{storage}..."
      sleep(0.5)
      puts "Dev database ready"
      sleep(0.3)
      @connection_string = "postgresql://localhost:5432/myapp_dev"
    end
  end
end

# Task that uses the database
class FetchData < Taski::Task
  exports :data

  def run
    db = DatabaseSection.connection_string
    puts "Connecting to #{db}..."
    sleep(0.3)
    puts "Querying records..."
    sleep(0.4)
    puts "Processing results..."
    sleep(0.3)
    @data = ["item1", "item2", "item3"]
  end
end

# Main application task
class Application < Taski::Task
  exports :result

  def run
    data = FetchData.data
    puts "Validating #{data.size} items..."
    sleep(0.3)
    puts "Transforming data..."
    sleep(0.4)
    puts "Finalizing results..."
    sleep(0.3)
    @result = "Processed: #{data.join(", ")}"
  end
end

# Show tree structure before execution
puts "Nested Section Tree Structure:"
puts "=" * 70
puts Application.tree
puts "=" * 70
puts

# Reset for execution
Application.reset!

# Execute
result = Application.result

puts "\n"
puts "=" * 70
puts "Execution completed!"
puts "Result: #{result}"
