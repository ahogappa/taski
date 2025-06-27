#!/usr/bin/env ruby
# frozen_string_literal: true

# Taski Progress Display Demo
#
# This comprehensive example demonstrates all progress display features:
# 1. Basic spinner animation with success/failure indicators
# 2. Output capture with 5-line tail display
# 3. Real-world build scenario with external command simulation
# 4. TTY detection for clean file output
#
# Run: ruby examples/progress_demo.rb
# Try: ruby examples/progress_demo.rb > build.log 2>&1 && cat build.log

require_relative "../lib/taski"

puts "🎯 Taski Progress Display Demo"
puts "=" * 50

# SECTION 1: Basic Spinner Animation
puts "\n📍 SECTION 1: Basic Spinner & Success/Failure Indicators"
puts "-" * 50

class ConfigTask < Taski::Task
  exports :database_url, :cache_url

  def build
    sleep 0.8
    @database_url = "postgres://localhost/myapp"
    @cache_url = "redis://localhost:6379"
  end
end

class DatabaseTask < Taski::Task
  exports :connection

  def build
    sleep 1.2 
    @connection = "Connected to #{ConfigTask.database_url}"
  end
end

class ApplicationTask < Taski::Task
  exports :status

  def build
    sleep 1.0
    db = DatabaseTask.connection
    @status = "App ready! #{db}"
  end
end

ApplicationTask.build
puts "🎉 Application Status: #{ApplicationTask.status}"

# SECTION 2: Output Capture Demo
puts "\n📍 SECTION 2: Output Capture with 5-Line Tail"
puts "-" * 50

class VerboseTask < Taski::Task
  exports :result

  def build
    puts "Starting task initialization..."
    sleep 0.3
    
    puts "Loading configuration files..."
    puts "Connecting to database..."
    puts "Connection established: localhost:5432"
    sleep 0.3
    
    puts "Running initial checks..."
    puts "Checking schema version..."
    puts "Schema is up to date"
    puts "Performing data validation..."
    puts "Validating user records..."
    puts "Validating product records..."
    puts "All validations passed"
    sleep 0.4
    
    puts "Task completed successfully!"
    @result = "All operations completed"
  end
end

VerboseTask.build
puts "📊 Verbose Task Result: #{VerboseTask.result}"

# SECTION 3: Production Build Scenario
puts "\n📍 SECTION 3: Production Build Scenario"
puts "-" * 50

class CompileTask < Taski::Task
  exports :result

  def build
    puts "Starting compilation process..."
    sleep 0.8

    puts "Checking source files..."
    puts "Found: main.c, utils.c, config.h"
    sleep 0.6

    puts "Running gcc compilation..."
    puts "gcc -Wall -O2 -c main.c"
    puts "gcc -Wall -O2 -c utils.c"
    puts "main.c: In function 'main':"
    puts "main.c:42: warning: unused variable 'temp'"
    puts "utils.c: In function 'parse_config':"
    puts "utils.c:15: warning: implicit declaration of function 'strcpy'"
    sleep 0.8

    puts "Linking objects..."
    puts "gcc -o myapp main.o utils.o"
    puts "Compilation successful!"

    @result = "myapp binary created"
  end
end

class TestTask < Taski::Task
  exports :test_result

  def build
    puts "Running test suite..."
    sleep 0.2

    (1..8).each do |i|
      puts "Test #{i}/8: #{['PASS', 'PASS', 'FAIL', 'PASS', 'PASS', 'PASS', 'PASS', 'PASS'][i-1]}"
      sleep 0.4
    end

    puts "Test summary: 7/8 passed, 1 failed"
    @test_result = "Tests completed with 1 failure"
  end
end

CompileTask.build
puts "📦 Compilation: #{CompileTask.result}"

TestTask.build
puts "🧪 Test Result: #{TestTask.test_result}"

# SECTION 4: Error Handling Demo
puts "\n📍 SECTION 4: Error Handling Demo"
puts "-" * 50

class FailingTask < Taski::Task
  def build
    puts "Attempting network connection..."
    sleep 1.0  # Watch it spin before failing
    puts "Connection timeout after 30 seconds"
    puts "Retrying connection..."
    sleep 0.5
    raise StandardError, "Network connection failed!"
  end
end

begin
  FailingTask.build
rescue Taski::TaskBuildError => e
  puts "🛡️  Error handled gracefully: #{e.message}"
end

puts "\n✨ Demo Complete!"
puts "Note: Rich spinner display only appears in terminals, not when output is redirected."