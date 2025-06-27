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

puts "\n▶️  Building Application (to verify dependencies work):"
Application.build
