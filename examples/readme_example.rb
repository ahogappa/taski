#!/usr/bin/env ruby
# Quick Start example from README

require_relative "../lib/taski"

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
puts "=== Quick Start Example ==="
APIServer.build

puts "\nResult: APIServer running on port #{APIServer.port}"
