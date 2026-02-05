#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/taski"

# Demo for group blocks in progress display
# Run with: ruby examples/group_demo.rb
#
# Groups organize output messages within a task into logical phases,
# displayed as children of the task in the progress tree.

class ConfigTask < Taski::Task
  exports :config

  def run
    group("Loading configuration") do
      puts "Reading config file..."
      sleep(0.2)
      puts "Parsing YAML..."
      sleep(0.1)
      puts "Config loaded"
    end

    @config = {
      database_url: "postgresql://localhost/myapp",
      redis_url: "redis://localhost:6379"
    }
  end
end

class BuildTask < Taski::Task
  exports :artifacts

  def run
    ConfigTask.config # Ensure config is loaded

    group("Compiling source") do
      puts "Analyzing dependencies..."
      sleep(0.2)
      puts "Compiling 42 files..."
      sleep(0.3)
      puts "Compilation complete"
    end

    group("Running tests") do
      puts "Running unit tests..."
      sleep(0.2)
      puts "Running integration tests..."
      sleep(0.2)
      puts "All 128 tests passed"
    end

    group("Bundling assets") do
      puts "Minifying JavaScript..."
      sleep(0.1)
      puts "Optimizing images..."
      sleep(0.2)
      puts "Assets bundled"
    end

    @artifacts = ["app.js", "app.css", "images/"]
  end
end

class DeployTask < Taski::Task
  exports :deploy_url

  def run
    artifacts = BuildTask.artifacts

    group("Preparing deployment") do
      puts "Creating deployment package..."
      sleep(0.2)
      puts "Package size: 12.5 MB"
    end

    group("Uploading to server") do
      puts "Connecting to server..."
      sleep(0.1)
      puts "Uploading #{artifacts.size} artifacts..."
      sleep(0.3)
      puts "Upload complete"
    end

    group("Starting application") do
      puts "Stopping old instance..."
      sleep(0.1)
      puts "Starting new instance..."
      sleep(0.2)
      puts "Health check passed"
    end

    @deploy_url = "https://app.example.com"
  end
end

# Show tree structure before execution
puts "Task Tree Structure:"
puts "=" * 60
puts DeployTask.tree
puts "=" * 60
puts

# Reset for execution
DeployTask.reset!

# Execute with progress display
url = DeployTask.deploy_url

puts "\n"
puts "=" * 60
puts "Deployment completed!"
puts "Application URL: #{url}"
