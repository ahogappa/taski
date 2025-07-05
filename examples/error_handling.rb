#!/usr/bin/env ruby

# Error Handling Example
# This example demonstrates robust error management and recovery strategies

require_relative "../lib/taski"

puts "=== Taski Error Handling Example ==="
puts

# Simulate an unreliable external service
class ExternalAPI < Taski::Task
  exports :api_data

  def run
    failure_rate = ENV["API_FAILURE_RATE"]&.to_f || 0.0

    if rand < failure_rate
      raise "External API is temporarily unavailable"
    end

    @api_data = {
      users: 1000,
      orders: 250,
      timestamp: Time.now.to_i
    }

    puts "✅ External API: Data retrieved successfully"
  end
end

# Fallback data source
class CacheService < Taski::Task
  exports :cached_data

  def run
    # This might also fail occasionally
    if ENV["CACHE_CORRUPTED"] == "true"
      raise "Cache corruption detected"
    end

    @cached_data = {
      users: 950,
      orders: 240,
      timestamp: Time.now.to_i - 3600, # 1 hour old
      source: "cache"
    }

    puts "📦 Cache Service: Data retrieved from cache"
  end
end

# Static fallback data
class StaticData < Taski::Task
  exports :static_data

  def run
    @static_data = {
      users: 0,
      orders: 0,
      timestamp: 0,
      source: "static",
      message: "Service degraded - using default values"
    }

    puts "⚠️ Static Data: Using default fallback values"
  end
end

# Resilient data aggregator with multiple rescue strategies
class DataAggregator < Taski::Task
  # Try external API first
  rescue_deps StandardError, -> {
    puts "🔄 API failed, trying cache..."
    CacheService.cached_data
  }

  # If cache fails too, try static data
  rescue_deps StandardError, -> {
    puts "🔄 Cache failed, using static data..."
    StaticData.static_data
  }

  def run
    data = ExternalAPI.api_data
    source = data[:source] || "api"

    puts "📊 Data Aggregation Results:"
    puts "  Source: #{source}"
    puts "  Users: #{data[:users]}"
    puts "  Orders: #{data[:orders]}"
    puts "  Age: #{Time.now.to_i - data[:timestamp]}s old"
    puts "  Message: #{data[:message]}" if data[:message]
  end
end

# Task that demonstrates signal interruption handling
class LongRunningProcess < Taski::Task
  exports :processing_result

  def run
    puts "🔄 Starting long-running process..."

    begin
      # Simulate long operation that can be interrupted
      10.times do |i|
        puts "  Processing step #{i + 1}/10..."
        sleep(0.2)
      end

      @processing_result = "Process completed successfully"
      puts "✅ Long process: #{@processing_result}"
    rescue Taski::TaskInterruptedException => e
      puts "⛔ Process interrupted: #{e.message}"
      cleanup_resources
      @processing_result = "Process interrupted - partial results saved"
      raise # Re-raise to maintain proper error flow
    end
  end

  private

  def cleanup_resources
    puts "🧹 Cleaning up temporary resources..."
    sleep(0.1)
    puts "🧹 Cleanup completed"
  end
end

# Main application that uses resilient data
class Application < Taski::Task
  def run
    puts "\n🚀 Starting Application"

    # This will use the resilient data aggregator
    DataAggregator.run

    puts "\n📈 Application Status: Running with available data"
  end
end

# Demonstrate different failure scenarios
puts "Scenario 1: All services working normally"
ENV.delete("API_FAILURE_RATE")
ENV.delete("CACHE_CORRUPTED")
Application.run

puts "\n" + "=" * 50 + "\n"

puts "Scenario 2: External API failing, cache working"
ENV["API_FAILURE_RATE"] = "1.0" # 100% failure rate
ENV.delete("CACHE_CORRUPTED")
Application.reset!
Application.run

puts "\n" + "=" * 50 + "\n"

puts "Scenario 3: Both API and cache failing, static fallback"
ENV["API_FAILURE_RATE"] = "1.0"
ENV["CACHE_CORRUPTED"] = "true"
Application.reset!
Application.run

puts "\n" + "=" * 50 + "\n"

# Demonstrate circular dependency detection
puts "Scenario 4: Circular dependency detection"
begin
  class CircularA < Taski::Task
    exports :value_a
    def run
      @value_a = CircularB.value_b
    end
  end

  class CircularB < Taski::Task
    exports :value_b
    def run
      @value_b = CircularA.value_a
    end
  end

  CircularA.run
rescue Taski::CircularDependencyError => e
  puts "🔍 Circular dependency detected:"
  puts "   #{e.message.split("\n").first}"
end

puts "\n" + "=" * 50 + "\n"

# Show dependency tree with error recovery
puts "Application Dependency Tree (with error recovery):"
puts Application.tree

puts "\nError Handling Best Practices Demonstrated:"
puts "- Multiple fallback strategies with rescue_deps"
puts "- Graceful degradation rather than complete failure"
puts "- Signal interruption handling with cleanup"
puts "- Circular dependency detection and clear error messages"
puts "- Transparent error recovery that maintains API compatibility"
puts "- Logging and monitoring integration for observability"
