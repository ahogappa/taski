# Advanced Features

This guide covers Taski's advanced features including progress display, signal handling, logging, and lifecycle management.

## Progress Display

Taski provides rich visual feedback during task execution with animated spinners and real-time output capture.

### Basic Progress Display

```ruby
class LongRunningTask < Taski::Task
  def run
    puts "Starting process..."
    sleep(1.0)
    puts "Processing data..."
    puts "Almost done..."
    sleep(0.5)
    puts "Completed!"
  end
end

LongRunningTask.run
# During execution shows:
# ⠧ LongRunningTask
#   Starting process...
#   Processing data...
#   Almost done...
#   Completed!
#
# After completion shows:
# ✅ LongRunningTask (1500ms)
```

### Progress Display Features

- **Spinner Animation**: Dots-style spinner during task execution
- **Output Capture**: Real-time display of task output (last 5 lines)
- **Status Indicators**: ✅ for success, ❌ for failure
- **Execution Time**: Shows task duration after completion
- **TTY Detection**: Clean output when redirected to files

### Complex Build Pipeline Example

```ruby
class CompileAssets < Taski::Task
  def run
    puts "Compiling SCSS..."
    sleep(0.8)
    puts "Processing JavaScript..."
    sleep(1.2)
    puts "Optimizing images..."
    sleep(0.5)
    puts "Assets compiled successfully"
  end
end

class RunTests < Taski::Task
  def run
    puts "Running unit tests..."
    sleep(2.0)
    puts "Running integration tests..."
    sleep(1.5)
    puts "All tests passed"
  end
end

class DeployApp < Taski::Task
  def run
    puts "Building Docker image..."
    CompileAssets.run
    puts "Running test suite..."
    RunTests.run
    puts "Deploying to production..."
    sleep(1.0)
    puts "Deployment complete"
  end
end

DeployApp.run
# Shows nested progress with clear hierarchy and timing
```

### File Output Mode

When output is redirected to a file, Taski automatically disables the interactive spinner:

```bash
# Interactive mode with spinner
ruby build.rb

# Clean output mode for logging
ruby build.rb > build.log 2>&1
cat build.log
# ✅ CompileAssets (800ms)
# ✅ RunTests (3500ms)  
# ✅ DeployApp (6200ms)
```

## Signal Handling

Taski supports graceful task interruption with comprehensive signal handling.

### Basic Signal Handling

```ruby
class LongRunningTask < Taski::Task
  def run
    puts "Starting long operation..."
    perform_long_operation
  rescue Taski::TaskInterruptedException => e
    puts "Task was interrupted: #{e.message}"
    cleanup_resources
    raise  # Re-raise to maintain proper error handling
  end
  
  private
  
  def perform_long_operation
    # Long running operation that can be interrupted
    100.times do |i|
      puts "Processing item #{i + 1}/100..."
      sleep(0.1)  # Simulated work
    end
  end
  
  def cleanup_resources
    puts "Cleaning up temporary files..."
    puts "Closing database connections..."
    puts "Cleanup complete"
  end
end

# Task can be interrupted with Ctrl+C (SIGINT) or SIGTERM
LongRunningTask.run
```

### Signal Handling Features

- **Multiple Signals**: Supports INT, TERM, USR1, USR2
- **Exception Conversion**: Converts signals to TaskInterruptedException
- **Test Environment**: Automatically disabled in test environments
- **Graceful Shutdown**: Allows cleanup before termination

### Advanced Signal Handling

```ruby
class DatabaseMigration < Taski::Task
  def run
    puts "Starting database migration..."
    
    begin
      migrate_tables
    rescue Taski::TaskInterruptedException => e
      puts "Migration interrupted: #{e.message}"
      rollback_partial_changes
      raise
    end
    
    puts "Migration completed successfully"
  end
  
  private
  
  def migrate_tables
    %w[users orders products].each do |table|
      puts "Migrating #{table} table..."
      sleep(2)  # Simulated migration time
    end
  end
  
  def rollback_partial_changes
    puts "Rolling back partial migration..."
    puts "Database restored to consistent state"
  end
end
```

## Error Recovery

Taski provides sophisticated error recovery mechanisms for handling dependency failures.

### Basic Error Recovery

```ruby
class DatabaseTask < Taski::Task
  exports :connection
  
  def run
    # This might fail in test environments
    @connection = connect_to_database
  end
  
  private
  
  def connect_to_database
    raise "Database connection failed" if ENV['FAIL_DB'] == 'true'
    "postgresql://localhost/myapp"
  end
end

class AppTask < Taski::Task
  # Rescue dependency errors and provide fallback
  rescue_deps StandardError, -> { "fallback://localhost/sqlite" }
  
  def run
    # Uses DatabaseTask.connection, or fallback if DatabaseTask fails
    connection = DatabaseTask.connection
    puts "Using connection: #{connection}"
  end
end

ENV['FAIL_DB'] = 'true'
AppTask.run
# => Using connection: fallback://localhost/sqlite
```

### Multiple Rescue Strategies

```ruby
class ExternalApiTask < Taski::Task
  exports :data
  
  def run
    @data = fetch_from_api
  end
  
  private
  
  def fetch_from_api
    raise "API unavailable" if ENV['API_DOWN'] == 'true'
    { users: 100, orders: 50 }
  end
end

class CacheTask < Taski::Task
  exports :cached_data
  
  def run
    @cached_data = load_from_cache
  end
  
  private
  
  def load_from_cache
    raise "Cache miss" if ENV['CACHE_MISS'] == 'true'
    { users: 95, orders: 48 }  # Slightly stale data
  end
end

class DataAggregator < Taski::Task
  # Try API first, then cache, then static fallback
  rescue_deps StandardError, -> { ExternalApiTask.data }
  rescue_deps StandardError, -> { CacheTask.cached_data }
  rescue_deps StandardError, -> { { users: 0, orders: 0 } }
  
  def run
    data = ExternalApiTask.data
    puts "Data aggregated: #{data}"
  end
end

# Test different failure scenarios
ENV['API_DOWN'] = 'true'
DataAggregator.run
# => Data aggregated: {users: 95, orders: 48}  # Falls back to cache

ENV['CACHE_MISS'] = 'true'
DataAggregator.reset!
DataAggregator.run
# => Data aggregated: {users: 0, orders: 0}    # Falls back to static data
```

### Error Recovery Features

- **Dependency Rescue**: Automatic fallback for failed dependencies
- **Custom Handlers**: Lambda-based error handling
- **Chain of Responsibility**: Multiple rescue strategies
- **Transparent Fallback**: Seamless error recovery

## Advanced Logging

Taski provides comprehensive logging with multiple formats and detailed performance monitoring.

### Logging Configuration

```ruby
# Configure logging level
Taski.logger.level = Logger::DEBUG

# Configure logging format
Taski.logger.formatter = Taski::Logging::StructuredFormatter.new

# Available formatters:
# - SimpleFormatter (default)
# - StructuredFormatter  
# - JsonFormatter
```

### Structured Logging

```ruby
class MonitoredTask < Taski::Task
  def run
    Taski.logger.info "Task starting", 
                      task: self.class.name,
                      environment: ENV['RAILS_ENV']
    
    perform_work
    
    Taski.logger.info "Task completed", 
                      duration: "1.2s",
                      success: true
  end
  
  private
  
  def perform_work
    Taski.logger.debug "Processing data", 
                       items_count: 100,
                       batch_size: 10
    
    # Simulated work
    sleep(1.2)
  end
end

MonitoredTask.run
# Structured output:
# [INFO] Task starting (task=MonitoredTask, environment=development)
# [DEBUG] Processing data (items_count=100, batch_size=10)
# [INFO] Task completed (duration=1.2s, success=true)
```

### JSON Logging

```ruby
# Configure JSON formatter for machine-readable logs
Taski.logger.formatter = Taski::Logging::JsonFormatter.new

class ApiTask < Taski::Task
  exports :response_data
  
  def run
    Taski.logger.info "API request starting", 
                      endpoint: "/api/users",
                      method: "GET"
    
    @response_data = { users: 42 }
    
    Taski.logger.info "API request completed",
                      endpoint: "/api/users", 
                      status: 200,
                      response_size: @response_data.to_json.size
  end
end

ApiTask.run
# JSON output:
# {"timestamp":"2024-01-01T12:00:00Z","level":"INFO","message":"API request starting","endpoint":"/api/users","method":"GET"}
# {"timestamp":"2024-01-01T12:00:01Z","level":"INFO","message":"API request completed","endpoint":"/api/users","status":200,"response_size":12}
```

### Performance Monitoring

```ruby
class PerformanceTask < Taski::Task
  def run
    # Automatic performance logging is built-in
    slow_operation
    fast_operation
  end
  
  private
  
  def slow_operation
    Taski.logger.debug "Starting slow operation"
    sleep(2.0)
    Taski.logger.debug "Slow operation completed"
  end
  
  def fast_operation
    Taski.logger.debug "Starting fast operation"
    sleep(0.1)
    Taski.logger.debug "Fast operation completed"
  end
end

PerformanceTask.run
# Automatic timing logs:
# [INFO] Task build started (task=PerformanceTask, dependencies=0)
# [DEBUG] Starting slow operation
# [DEBUG] Slow operation completed
# [DEBUG] Starting fast operation
# [DEBUG] Fast operation completed
# [INFO] Task build completed (task=PerformanceTask, duration_ms=2100)
```

## Lifecycle Management

Taski supports comprehensive lifecycle management with run and clean methods.

### Basic Lifecycle

```ruby
class DatabaseSetup < Taski::Task
  exports :connection
  
  def run
    @connection = "postgresql://localhost:5432/myapp"
    puts "Database connected"
  end
  
  def clean
    puts "Database disconnected"
    # Cleanup logic here
  end
end

class WebServer < Taski::Task
  def run
    puts "Web server started with #{DatabaseSetup.connection}"
  end
  
  def clean
    puts "Web server stopped"
  end
end

# Start everything
WebServer.run
# => Database connected
# => Web server started with postgresql://localhost:5432/myapp

# Clean everything in reverse order
WebServer.clean
# => Web server stopped
# => Database disconnected
```

### Advanced Lifecycle with Resource Management

```ruby
class FileProcessor < Taski::Task
  exports :output_file, :temp_dir
  
  def run
    @temp_dir = "/tmp/processing_#{Time.now.to_i}"
    Dir.mkdir(@temp_dir)
    puts "Created temp directory: #{@temp_dir}"
    
    @output_file = "#{@temp_dir}/result.txt"
    File.write(@output_file, "Processing complete")
    puts "Created output file: #{@output_file}"
  end
  
  def clean
    if @output_file && File.exist?(@output_file)
      File.delete(@output_file)
      puts "Deleted output file: #{@output_file}"
    end
    
    if @temp_dir && Dir.exist?(@temp_dir)
      Dir.rmdir(@temp_dir)
      puts "Deleted temp directory: #{@temp_dir}"
    end
  end
end

class ReportGenerator < Taski::Task
  def run
    data = File.read(FileProcessor.output_file)
    puts "Generated report from: #{data}"
  end
  
  def clean
    puts "Report generation cleaned up"
  end
end

# Usage
ReportGenerator.run
# => Created temp directory: /tmp/processing_1234567890
# => Created output file: /tmp/processing_1234567890/result.txt
# => Generated report from: Processing complete

ReportGenerator.clean
# => Report generation cleaned up
# => Deleted output file: /tmp/processing_1234567890/result.txt
# => Deleted temp directory: /tmp/processing_1234567890
```

### Idempotent Clean Methods

**Important**: Clean methods must be idempotent - safe to call multiple times:

```ruby
class SafeFileTask < Taski::Task
  exports :data_file
  
  def run
    @data_file = '/tmp/safe_data.txt'
    File.write(@data_file, 'Important data')
  end
  
  def clean
    # ✅ Good: Check before delete
    if @data_file && File.exist?(@data_file)
      File.delete(@data_file)
      puts "Deleted #{@data_file}"
    else
      puts "File #{@data_file} already deleted or doesn't exist"
    end
  end
end

# Safe to call multiple times
task = SafeFileTask.new
task.run
task.clean  # => Deleted /tmp/safe_data.txt
task.clean  # => File /tmp/safe_data.txt already deleted or doesn't exist
```

## Dependency Tree Visualization

Visualize complex dependency relationships with the tree method:

```ruby
class Database < Taski::Task
  exports :connection
  def run; @connection = "db-conn"; end
end

class Cache < Taski::Task
  exports :redis_url
  def run; @redis_url = "redis://localhost"; end
end

class Config < Taski::Task
  exports :settings
  def run
    @settings = {
      database: Database.connection,
      cache: Cache.redis_url
    }
  end
end

class WebServer < Taski::Task
  def run
    puts "Starting with #{Config.settings}"
  end
end

puts WebServer.tree
# => WebServer
# => └── Config
# =>     ├── Database
# =>     └── Cache

# Complex hierarchies are clearly visualized
class ApiGateway < Taski::Task
  def run
    puts "Gateway starting with #{Config.settings}"
    puts "Using cache: #{Cache.redis_url}"
  end
end

puts ApiGateway.tree
# => ApiGateway
# => ├── Config
# => │   ├── Database
# => │   └── Cache
# => └── Cache
```

## Performance Tips

### 1. Use Appropriate Reset Strategies

```ruby
# Reset specific tasks when needed
DatabaseTask.reset!  # Only resets this task
AppTask.reset!       # Resets this task and triggers dependency rebuilds

# Reset entire dependency tree
Taski::Task.reset_all!  # Nuclear option - resets everything
```

### 2. Optimize Long-Running Tasks

```ruby
class OptimizedTask < Taski::Task
  def run
    # Break long operations into chunks for better progress display
    (1..100).each_slice(10) do |batch|
      puts "Processing batch: #{batch.first}-#{batch.last}"
      process_batch(batch)
    end
  end
  
  private
  
  def process_batch(items)
    # Process items in batch
    sleep(0.1)  # Simulated work
  end
end
```

### 3. Use Structured Logging for Debugging

```ruby
class DebuggableTask < Taski::Task
  def run
    Taski.logger.debug "Task configuration", 
                       config: get_config,
                       dependencies: self.class.dependencies.map(&:name)
    
    perform_work
  end
end
```

This comprehensive guide covers all of Taski's advanced features. Each feature is designed to work seamlessly together, providing a robust foundation for complex task orchestration.