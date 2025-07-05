#!/usr/bin/env ruby

# Define API Basics Example
# This example demonstrates dynamic dependencies with the Define API

require_relative "../lib/taski"

puts "=== Taski Define API Basics Example ==="
puts

# Define API is perfect for environment-based logic and runtime computation
class EnvironmentConfig < Taski::Task
  # Define API uses lambdas to compute values at runtime
  define :database_host, -> {
    case ENV["RAILS_ENV"]
    when "production"
      "prod-db.example.com"
    when "staging"
      "staging-db.example.com"
    else
      "localhost"
    end
  }

  define :debug_mode, -> {
    ENV["DEBUG"] == "true"
  }

  define :max_connections, -> {
    debug_mode ? 5 : 100  # Can reference other define values
  }

  def run
    puts "Environment Configuration:"
    puts "  Database Host: #{database_host}"
    puts "  Debug Mode: #{debug_mode}"
    puts "  Max Connections: #{max_connections}"
  end
end

# Feature flags are a perfect use case for Define API
class FeatureFlags < Taski::Task
  define :use_new_ui, -> {
    ENV["NEW_UI"] == "true"
  }

  define :enable_caching, -> {
    # Complex logic can be used in define blocks
    return false if ENV["DISABLE_CACHE"] == "true"
    return true if ENV["ENABLE_CACHE"] == "true"

    # Default: enable in production
    ENV["RAILS_ENV"] == "production"
  }

  def run
    puts "Feature Flags:"
    puts "  New UI: #{use_new_ui ? "Enabled" : "Disabled"}"
    puts "  Caching: #{enable_caching ? "Enabled" : "Disabled"}"
  end
end

# Tasks can depend on Define API values from other tasks
class ApplicationServer < Taski::Task
  define :server_config, -> {
    {
      host: EnvironmentConfig.database_host,
      debug: EnvironmentConfig.debug_mode,
      cache_enabled: FeatureFlags.enable_caching,
      ui_version: FeatureFlags.use_new_ui ? "v2" : "v1"
    }
  }

  def run
    config = server_config
    puts "Starting Application Server:"
    puts "  Connecting to: #{config[:host]}"
    puts "  Debug mode: #{config[:debug]}"
    puts "  Cache: #{config[:cache_enabled] ? "enabled" : "disabled"}"
    puts "  UI Version: #{config[:ui_version]}"
  end
end

# Demonstrate different environments
puts "1. Development Environment (default):"
ENV["RAILS_ENV"] = "development"
ENV.delete("DEBUG")
ENV.delete("NEW_UI")
ApplicationServer.run

puts "\n" + "=" * 50 + "\n"

puts "2. Production Environment with features:"
ENV["RAILS_ENV"] = "production"
ENV["DEBUG"] = "true"
ENV["NEW_UI"] = "true"

# Reset tasks to re-evaluate define blocks
ApplicationServer.reset!
ApplicationServer.run

puts "\n" + "=" * 50 + "\n"

puts "3. Staging Environment:"
ENV["RAILS_ENV"] = "staging"
ENV.delete("DEBUG")
ENV.delete("NEW_UI")
ENV["DISABLE_CACHE"] = "true"

ApplicationServer.reset!
ApplicationServer.run

puts "\n" + "=" * 50 + "\n"

# Show dependency tree
puts "Dependency Tree:"
puts ApplicationServer.tree

puts "\nKey Takeaways:"
puts "- Define API computes values at runtime, not class definition time"
puts "- Perfect for environment-specific logic and feature flags"
puts "- Values are cached until task.reset! is called"
puts "- Can reference other define values within the same task"
puts "- Static analysis still works - dependencies are detected"
