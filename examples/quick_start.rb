#!/usr/bin/env ruby
# frozen_string_literal: true

# Taski Quick Start Guide
#
# This example demonstrates the fundamentals of Taski:
# - Task definition with the Exports API
# - Automatic dependency resolution
# - Simple task execution
#
# Run: ruby examples/quick_start.rb

require_relative "../lib/taski"

puts "🚀 Taski Quick Start"
puts "=" * 30

# Simple static dependency using Exports API
class DatabaseSetup < Taski::Task
  exports :connection_string

  def build
    @connection_string = "postgresql://localhost/myapp"
    puts "Database configured"
  end
end

class APIServer < Taski::Task
  exports :port

  def build
    # Automatic dependency: DatabaseSetup will be built first
    puts "Starting API with #{DatabaseSetup.connection_string}"
    @port = 3000
  end
end

# Execute - dependencies are resolved automatically
APIServer.build

puts "\n✅ Result: APIServer running on port #{APIServer.port}"