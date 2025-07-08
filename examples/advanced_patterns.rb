#!/usr/bin/env ruby
# frozen_string_literal: true

# Taski Advanced Patterns
#
# This example demonstrates advanced Taski patterns:
# - Mixed usage of Exports API and Define API
# - Environment-specific dependency resolution
# - Feature flag integration with dynamic dependencies
# - Task reset and rebuild scenarios
# - Conditional dependency evaluation
#
# Run: ruby examples/advanced_patterns.rb

require_relative "../lib/taski"

puts "⚡ Advanced Taski Patterns"
puts "=" * 40

# Mock classes for the example
class ProductionDB < Taski::Task
  exports :connection_string
  def run
    @connection_string = "postgres://prod-server/app"
  end
end

class TestDB < Taski::Task
  exports :connection_string
  def run
    @connection_string = "postgres://test-server/app_test"
  end
end

module FeatureFlag
  def self.enabled?(flag)
    ENV["FEATURE_#{flag.to_s.upcase}"] == "true"
  end
end

class RedisService < Taski::Task
  exports :configuration
  def run
    @configuration = "redis://localhost:6379"
  end
end

# Environment configuration using Define API
class Environment < Taski::Task
  define :database_url, -> {
    case ENV["RAILS_ENV"]
    when "production"
      ProductionDB.connection_string
    when "test"
      TestDB.connection_string
    else
      "sqlite3://development.db"
    end
  }

  define :redis_config, -> {
    if FeatureFlag.enabled?(:redis_cache)
      RedisService.configuration
    end
  }

  def run
    # Environment configuration is handled by define blocks
  end
end

# Static configuration using Exports API
class AppConfig < Taski::Task
  exports :app_name, :version, :port

  def run
    @app_name = "MyWebApp"
    @version = "2.1.0"
    @port = ENV.fetch("PORT", 3000).to_i
  end
end

# Application startup combining both APIs
class Application < Taski::Task
  def run
    puts "Starting #{AppConfig.app_name} v#{AppConfig.version}"
    puts "Database: #{Environment.database_url}"
    puts "Redis: #{Environment.redis_config || "disabled"}"
    puts "Port: #{AppConfig.port}"
  end

  def clean
    puts "Shutting down #{AppConfig.app_name}..."
  end
end

# Test different environments
puts "\n1. Development Environment (default):"
ENV.delete("RAILS_ENV")
ENV.delete("FEATURE_REDIS_CACHE")
Application.run
Application.reset!

puts "\n2. Test Environment:"
ENV["RAILS_ENV"] = "test"
# Reset Environment to re-evaluate define blocks
Environment.reset!
Application.run
Application.reset!

puts "\n3. Production with Redis:"
ENV["RAILS_ENV"] = "production"
ENV["FEATURE_REDIS_CACHE"] = "true"
# Reset Environment to re-evaluate define blocks
Environment.reset!
Application.run

puts "\n4. Parametrized Task Execution (run_with_args):"

# Task that accepts parameters
class ParametrizedTask < Taski::Task
  exports :result

  def run
    # Access parameters using build_args method
    args = run_args
    multiplier = args[:multiplier] || 1
    base_value = args[:base_value] || 10

    @result = base_value * multiplier
    puts "Computed result: #{@result} (base: #{base_value}, multiplier: #{multiplier})"
  end
end

# Task that uses parametrized dependency
class Calculator < Taski::Task
  def run
    # Use parameters to customize calculation
    args = run_args
    multiplier = args[:multiplier] || 1
    base_value = args[:base_value] || 10

    puts "Calculator running with multiplier: #{multiplier}, base_value: #{base_value}"

    result = base_value * multiplier
    puts "Final result: #{result}"
  end
end

# Example 1: Basic parametrized task execution
puts "Basic parametrized task execution:"
Calculator.run(multiplier: 2, base_value: 5)

# Example 2: Different parameters
puts "\nDifferent parameters:"
Calculator.run(multiplier: 3, base_value: 10)

# Example 3: Using ParametrizedTask with parameters
puts "\nParametrized task with dependency:"
result = ParametrizedTask.run(multiplier: 4, base_value: 7)
puts "Parametrized task result: #{result.result}"

puts "\n5. Cleanup:"
puts "Application shutdown complete"
