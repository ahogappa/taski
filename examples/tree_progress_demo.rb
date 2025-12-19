#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/taski"

# Demo for tree-based progress display
# Run with: TASKI_FORCE_PROGRESS=1 ruby examples/tree_progress_demo.rb

# Database configuration section with multiple impl candidates
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
      sleep(0.5)
      puts "Production DB connected"
      @connection_string = "postgresql://prod-server:5432/myapp"
    end
  end

  class DevelopmentDB < Taski::Task
    def run
      puts "Connecting to development database..."
      sleep(0.3)
      puts "Development DB connected"
      @connection_string = "postgresql://localhost:5432/myapp_dev"
    end
  end
end

# API section with multiple impl candidates
class ApiSection < Taski::Section
  interfaces :base_url

  def impl
    if ENV["USE_STAGING_API"] == "1"
      StagingApi
    else
      ProductionApi
    end
  end

  class ProductionApi < Taski::Task
    def run
      puts "Initializing production API..."
      sleep(0.4)
      @base_url = "https://api.example.com"
    end
  end

  class StagingApi < Taski::Task
    def run
      puts "Initializing staging API..."
      sleep(0.2)
      @base_url = "https://staging.api.example.com"
    end
  end
end

# Task with stdout output
class FetchUserData < Taski::Task
  exports :users

  def run
    puts "Fetching users from database..."
    sleep(0.3)
    puts "Found 100 users"
    sleep(0.2)
    puts "Processing user records..."
    sleep(0.3)
    puts "User data ready"
    @users = ["Alice", "Bob", "Charlie"]
  end
end

class FetchProductData < Taski::Task
  exports :products

  def run
    puts "Loading product catalog..."
    sleep(0.4)
    puts "Fetched 50 products"
    sleep(0.2)
    puts "Indexing products..."
    sleep(0.3)
    @products = ["Widget", "Gadget", "Thing"]
  end
end

class BuildReport < Taski::Task
  exports :report

  def run
    db = DatabaseSection.connection_string
    api = ApiSection.base_url
    users = FetchUserData.users
    products = FetchProductData.products

    puts "Building report..."
    sleep(0.2)
    puts "Aggregating data from #{users.size} users..."
    sleep(0.3)
    puts "Processing #{products.size} products..."
    sleep(0.2)
    puts "Report generated successfully"

    @report = {
      database: db,
      api: api,
      user_count: users.size,
      product_count: products.size
    }
  end
end

class SendNotification < Taski::Task
  exports :notification_sent

  def run
    BuildReport.report
    puts "Sending notification..."
    sleep(0.2)
    puts "Email sent to admin@example.com"
    @notification_sent = true
  end
end

class Application < Taski::Task
  exports :status

  def run
    notification = SendNotification.notification_sent
    puts "Application startup complete"
    @status = notification ? "success" : "failed"
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

# Execute with tree progress display (start/stop handled automatically by Executor)
result = Application.status

puts "\n"
puts "=" * 60
puts "Execution completed!"
puts "Status: #{result}"
puts "Report: #{BuildReport.report.inspect}"
