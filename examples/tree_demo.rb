#!/usr/bin/env ruby
# frozen_string_literal: true

# Tree Display Demo
#
# This example demonstrates the tree display functionality that shows
# task dependency relationships in a visual tree format.
#
# Run: ruby examples/tree_demo.rb

require_relative "../lib/taski"

puts "🌲 Taski Tree Display Demo"
puts "=" * 40

# Create a dependency chain for demonstration
class Database < Taski::Task
  exports :connection_string

  def build
    @connection_string = "postgres://localhost/myapp"
  end
end

class Cache < Taski::Task
  exports :redis_url

  def build
    @redis_url = "redis://localhost:6379"
  end
end

class Config < Taski::Task
  exports :settings

  def build
    @settings = {
      database: Database.connection_string,
      cache: Cache.redis_url,
      port: 3000
    }
  end
end

class Logger < Taski::Task
  exports :log_level

  def build
    @log_level = "info"
  end
end

class WebServer < Taski::Task
  exports :server_instance

  def build
    @server_instance = "WebServer configured with #{Config.settings[:database]} and #{Logger.log_level}"
  end
end

class Application < Taski::Task
  def build
    puts "Starting application..."
    puts "Web server: #{WebServer.server_instance}"
    puts "Config: #{Config.settings}"
  end
end

puts "\n📊 Application Dependency Tree:"
puts Application.tree

puts "\n🔍 Individual Component Trees:"
puts "\nWebServer dependencies:"
puts WebServer.tree

puts "\nConfig dependencies:"
puts Config.tree

puts "\n🔧 Section-based Architecture (Dynamic Implementation Selection):"

# Create database section with multiple implementation options
class DatabaseSection < Taski::Section
  interface :connection_string, :pool_size

  def self.impl
    if ENV["DATABASE"] == "postgres"
      PostgresImplementation
    elsif ENV["DATABASE"] == "mysql"
      MysqlImplementation
    else
      SQLiteImplementation
    end
  end

  class PostgresImplementation < Taski::Task
    exports :connection_string, :pool_size

    def build
      Logger.log_level
      @connection_string = "postgresql://localhost/production_app"
      @pool_size = 20
    end
  end

  class MysqlImplementation < Taski::Task
    exports :connection_string, :pool_size

    def build
      Logger.log_level
      @connection_string = "mysql://localhost/production_app"
      @pool_size = 15
    end
  end

  class SQLiteImplementation < Taski::Task
    exports :connection_string, :pool_size

    def build
      @connection_string = "sqlite:///tmp/development.db"
      @pool_size = 1
    end
  end
end

# Cache section with Redis/Memory options
class CacheSection < Taski::Section
  interface :cache_url

  def self.impl
    if ENV["CACHE"] == "redis"
      RedisCache
    else
      MemoryCache
    end
  end

  class RedisCache < Taski::Task
    exports :cache_url
    def build
      DatabaseSection.connection_string
      @cache_url = "redis://localhost:6379"
    end
  end

  class MemoryCache < Taski::Task
    exports :cache_url
    def build
      @cache_url = "memory://local"
    end
  end
end

puts "\n📋 Section Trees (Show Available Implementations):"
puts "\nDatabaseSection.tree:"
puts DatabaseSection.tree

puts "\nCacheSection.tree:"
puts CacheSection.tree

puts "\n🔍 Individual Implementation Trees (Show Actual Dependencies):"
puts "\nDatabaseSection::PostgresImplementation.tree:"
puts DatabaseSection::PostgresImplementation.tree

puts "\nDatabaseSection::SQLiteImplementation.tree:"
puts DatabaseSection::SQLiteImplementation.tree

puts "\nCacheSection::RedisCache.tree:"
puts CacheSection::RedisCache.tree

puts "\n🔄 Section vs Implementation Comparison:"
puts "Section shows POSSIBLE implementations:"
puts DatabaseSection.tree
puts "\nBut implementation shows ACTUAL dependencies:"
puts DatabaseSection::PostgresImplementation.tree

puts "\n💡 Workflow:"
puts "1. Use DatabaseSection.tree to see what implementations are available"
puts "2. Use DatabaseSection::PostgresImplementation.tree to see specific dependencies"
puts "3. Runtime selects implementation based on ENV variables"

puts "\n🎨 Colored Tree Display (if TTY supports colors):"

# Enable colors for demonstration
Taski::TreeColors.enabled = true

puts "\nDatabaseSection.tree (with colors):"
puts DatabaseSection.tree(color: true)

puts "\nCacheSection.tree (with colors):"
puts CacheSection.tree(color: true)

puts "\nDatabaseSection::PostgresImplementation.tree (with colors):"
puts DatabaseSection::PostgresImplementation.tree(color: true)

puts "\n🎯 Color Legend:"
puts "#{Taski::TreeColors.section("Blue")} = Section names (dynamic selection layer)"
puts "#{Taski::TreeColors.task("Green")} = Task names (concrete implementations)"
puts "#{Taski::TreeColors.implementations("Yellow")} = Implementation candidates"
puts "#{Taski::TreeColors.connector("Gray")} = Tree connectors"

# Reset colors to auto-detection
Taski::TreeColors.enabled = nil

puts "\n▶️  Building Application (to verify dependencies work):"
Application.build
