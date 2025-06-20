#!/usr/bin/env ruby
# Complex example from README showing both APIs

require_relative "../lib/taski"

# Mock classes for the example
class ProductionDB < Taski::Task
  exports :connection_string
  def build
    @connection_string = "postgres://prod-server/app"
  end
end

class TestDB < Taski::Task
  exports :connection_string
  def build
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
  def build
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

  def build
    # Environment configuration is handled by define blocks
  end
end

# Static configuration using Exports API
class AppConfig < Taski::Task
  exports :app_name, :version, :port

  def build
    @app_name = "MyWebApp"
    @version = "2.1.0"
    @port = ENV.fetch("PORT", 3000).to_i
  end
end

# Application startup combining both APIs
class Application < Taski::Task
  def build
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
puts "=== Complex Example ==="

puts "\n1. Development Environment (default):"
ENV.delete("RAILS_ENV")
ENV.delete("FEATURE_REDIS_CACHE")
Application.build
Application.reset!

puts "\n2. Test Environment:"
ENV["RAILS_ENV"] = "test"
# Reset Environment to re-evaluate define blocks
Environment.reset!
Application.build
Application.reset!

puts "\n3. Production with Redis:"
ENV["RAILS_ENV"] = "production"
ENV["FEATURE_REDIS_CACHE"] = "true"
# Reset Environment to re-evaluate define blocks
Environment.reset!
Application.build

puts "\n4. Cleanup:"
Application.clean
