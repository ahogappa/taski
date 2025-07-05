#!/usr/bin/env ruby

# Section API Basics Example
# This example demonstrates runtime implementation selection with the Section API

# Section API is perfect for:
# - Environment-specific implementations (dev/staging/prod)
# - Different service adapters (AWS/GCP/local)
# - Clean abstraction with guaranteed interfaces

require_relative "../lib/taski"

# Example 1: Database Configuration Section
# This section provides database configuration with different implementations
# for development and production environments
class DatabaseSection < Taski::Section
  # Define the interface that implementations must provide
  interface :host, :port, :username, :password, :database_name, :pool_size

  # Select implementation based on environment
  # Note: Must return a Task class - .run is automatically called
  # No 'self' needed - just define as instance method!
  def impl
    if ENV["RAILS_ENV"] == "production"
      Production
    else
      Development
    end
  end

  # Production implementation with secure settings
  # Note: exports are automatically inherited from interface declaration
  class Production < Taski::Task
    def run
      @host = "prod-db.example.com"
      @port = 5432
      @username = "app_user"
      @password = ENV["DB_PASSWORD"] || "secure_password"
      @database_name = "myapp_production"
      @pool_size = 25
    end
  end

  # Development implementation with local settings
  # Note: exports are automatically inherited from interface declaration
  class Development < Taski::Task
    def run
      @host = "localhost"
      @port = 5432
      @username = "dev_user"
      @password = "dev_password"
      @database_name = "myapp_development"
      @pool_size = 5
    end
  end
end

# Example 2: API Configuration Section
# This section provides API endpoints and credentials
class ApiSection < Taski::Section
  interface :base_url, :api_key, :timeout, :retry_count

  # No 'self' needed - just define as instance method!
  def impl
    # Select based on feature flag
    # Note: Must return a Task class - .run is automatically called
    if ENV["USE_STAGING_API"] == "true"
      Staging
    else
      Production
    end
  end

  # Note: exports are automatically inherited from interface declaration - DRY principle!
  class Production < Taski::Task
    def run
      @base_url = "https://api.example.com/v1"
      @api_key = ENV["PROD_API_KEY"] || "prod-key-123"
      @timeout = 30
      @retry_count = 3
    end
  end

  # Note: exports are automatically inherited from interface declaration - DRY principle!
  class Staging < Taski::Task
    def run
      @base_url = "https://staging-api.example.com/v1"
      @api_key = ENV["STAGING_API_KEY"] || "staging-key-456"
      @timeout = 60
      @retry_count = 1
    end
  end
end

# Example 3: Task that depends on multiple sections
class ApplicationSetup < Taski::Task
  exports :config_summary

  def run
    puts "Setting up application with configuration:"
    puts "Database: #{DatabaseSection.host}:#{DatabaseSection.port}/#{DatabaseSection.database_name}"
    puts "API: #{ApiSection.base_url}"
    puts "Pool size: #{DatabaseSection.pool_size}"
    puts "API timeout: #{ApiSection.timeout}s"

    @config_summary = {
      database: {
        host: DatabaseSection.host,
        port: DatabaseSection.port,
        database: DatabaseSection.database_name,
        pool_size: DatabaseSection.pool_size
      },
      api: {
        base_url: ApiSection.base_url,
        timeout: ApiSection.timeout,
        retry_count: ApiSection.retry_count
      }
    }
  end
end

# Example 4: Complex dependency chain with sections
class DatabaseConnection < Taski::Task
  exports :connection

  def run
    puts "Connecting to database..."
    # Use section configuration to create connection
    connection_string = "postgresql://#{DatabaseSection.username}:#{DatabaseSection.password}@#{DatabaseSection.host}:#{DatabaseSection.port}/#{DatabaseSection.database_name}"
    @connection = "Connected to: #{connection_string} (pool: #{DatabaseSection.pool_size})"
    puts @connection
  end
end

class ApiClient < Taski::Task
  exports :client

  def run
    puts "Initializing API client..."
    @client = "API Client: #{ApiSection.base_url} (timeout: #{ApiSection.timeout}s, retries: #{ApiSection.retry_count})"
    puts @client
  end
end

class Application < Taski::Task
  def run
    puts "\n=== Starting Application ==="

    # Dependencies are automatically resolved
    # DatabaseConnection and ApiClient will be executed first
    # which triggers execution of their respective sections

    puts "\nDatabase ready: #{DatabaseConnection.connection}"
    puts "API ready: #{ApiClient.client}"

    puts "\nApplication configuration summary:"
    puts ApplicationSetup.config_summary.inspect

    puts "\n=== Application Started Successfully ==="
  end
end

# Demo script
if __FILE__ == $0
  puts "Taski Section Configuration Example"
  puts "=" * 50

  puts "\n1. Development Environment (default)"
  ENV["RAILS_ENV"] = "development"
  ENV["USE_STAGING_API"] = "false"

  # Reset all tasks to ensure fresh build
  [DatabaseSection, ApiSection, ApplicationSetup, DatabaseConnection, ApiClient, Application].each(&:reset!)

  Application.run

  puts "\n" + "=" * 50
  puts "\n2. Production Environment with Staging API"
  ENV["RAILS_ENV"] = "production"
  ENV["USE_STAGING_API"] = "true"

  # Reset all tasks to see different configuration
  [DatabaseSection, ApiSection, ApplicationSetup, DatabaseConnection, ApiClient, Application].each(&:reset!)

  Application.run

  puts "\n" + "=" * 50
  puts "\n3. Dependency Tree Visualization"
  puts "\nApplication dependency tree:"
  puts Application.tree

  puts "\nDatabaseConnection dependency tree:"
  puts DatabaseConnection.tree

  puts "\nApiClient dependency tree:"
  puts ApiClient.tree

  puts "\n" + "=" * 50
  puts "\nSection dependency resolution successfully demonstrated!"
  puts "Notice how sections appear in the dependency trees and logs."
end
