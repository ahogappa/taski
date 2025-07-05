# Error Handling Guide

This guide covers Taski's comprehensive error handling capabilities including circular dependency detection, task build errors, and recovery strategies.

## Error Types

Taski provides specific exception types for different error scenarios:

- `Taski::CircularDependencyError`: Circular dependency detected
- `Taski::TaskBuildError`: Task execution failed
- `Taski::TaskAnalysisError`: Static analysis failed
- `Taski::SectionImplementationError`: Section implementation problems
- `Taski::TaskInterruptedException`: Task interrupted by signal

## Circular Dependency Detection

Taski automatically detects circular dependencies and provides detailed error messages.

### Simple Circular Dependency

```ruby
class TaskA < Taski::Task
  exports :value_a
  
  def run
    @value_a = TaskB.value_b  # TaskA depends on TaskB
  end
end

class TaskB < Taski::Task
  exports :value_b
  
  def run
    @value_b = TaskA.value_a  # TaskB depends on TaskA - CIRCULAR!
  end
end

begin
  TaskA.run
rescue Taski::CircularDependencyError => e
  puts "Error: #{e.message}"
end

# Output:
# Error: Circular dependency detected!
# Cycle: TaskA → TaskB → TaskA
# 
# The dependency chain is:
#   1. TaskA is trying to build → TaskB
#   2. TaskB is trying to build → TaskA
```

### Complex Circular Dependencies

```ruby
class DatabaseConfig < Taski::Task
  exports :connection_string
  
  def run
    # This creates a complex circular dependency
    @connection_string = "postgresql://#{ServerConfig.host}/#{AppConfig.database_name}"
  end
end

class ServerConfig < Taski::Task
  exports :host
  
  def run
    @host = AppConfig.production? ? "prod.example.com" : "localhost"
  end
end

class AppConfig < Taski::Task
  exports :database_name, :production
  
  def run
    @database_name = "myapp_#{DatabaseConfig.connection_string.split('/').last}"
    @production = ENV['RAILS_ENV'] == 'production'
  end
end

begin
  DatabaseConfig.run
rescue Taski::CircularDependencyError => e
  puts "Complex circular dependency detected:"
  puts e.message
end

# Output:
# Complex circular dependency detected:
# Circular dependency detected!
# Cycle: DatabaseConfig → AppConfig → DatabaseConfig
# 
# The dependency chain is:
#   1. DatabaseConfig is trying to build → AppConfig
#   2. AppConfig is trying to build → DatabaseConfig
```

### Avoiding Circular Dependencies

```ruby
# ❌ Bad: Circular dependency
class BadConfigA < Taski::Task
  exports :value
  def run; @value = BadConfigB.other_value; end
end

class BadConfigB < Taski::Task
  exports :other_value
  def run; @other_value = BadConfigA.value; end
end

# ✅ Good: Hierarchical dependencies
class BaseConfig < Taski::Task
  exports :environment, :base_url
  
  def run
    @environment = ENV['RAILS_ENV'] || 'development'
    @base_url = @environment == 'production' ? 'https://api.example.com' : 'http://localhost:3000'
  end
end

class DatabaseConfig < Taski::Task
  exports :connection_string
  
  def run
    db_name = BaseConfig.environment == 'production' ? 'myapp_prod' : 'myapp_dev'
    @connection_string = "postgresql://localhost/#{db_name}"
  end
end

class ApiConfig < Taski::Task
  exports :endpoint
  
  def run
    @endpoint = "#{BaseConfig.base_url}/api/v1"
  end
end
```

## Task Build Errors

When task execution fails, Taski wraps the error in a `TaskBuildError` with detailed context.

### Basic Error Handling

```ruby
class FailingTask < Taski::Task
  exports :result
  
  def run
    raise "Something went wrong!"
  end
end

class DependentTask < Taski::Task
  def run
    puts "Using result: #{FailingTask.result}"
  end
end

begin
  DependentTask.run
rescue Taski::TaskBuildError => e
  puts "Task build failed: #{e.message}"
  puts "Original error: #{e.cause.message}"
  puts "Failed task: #{e.task_class}"
end

# Output:
# Task build failed: Failed to build task FailingTask: Something went wrong!
# Original error: Something went wrong!
# Failed task: FailingTask
```

### Error Propagation

```ruby
class DatabaseTask < Taski::Task
  exports :connection
  
  def run
    raise "Database connection failed"
  end
end

class CacheTask < Taski::Task
  exports :redis_client
  
  def run
    @redis_client = "redis://localhost:6379"
  end
end

class ApplicationTask < Taski::Task
  def run
    # Both dependencies required
    db = DatabaseTask.connection
    cache = CacheTask.redis_client
    puts "App started with DB: #{db}, Cache: #{cache}"
  end
end

begin
  ApplicationTask.run
rescue Taski::TaskBuildError => e
  puts "Application failed to start:"
  puts "  Failed task: #{e.task_class}"
  puts "  Error: #{e.cause.message}"
  
  # Chain of errors is preserved
  current = e
  while current.cause
    current = current.cause
    puts "  Caused by: #{current.message}" if current.respond_to?(:message)
  end
end

# Output:
# Application failed to start:
#   Failed task: DatabaseTask
#   Error: Database connection failed
```

## Dependency Error Recovery

Taski provides powerful error recovery mechanisms using `rescue_deps`.

### Basic Error Recovery

```ruby
class UnreliableService < Taski::Task
  exports :data
  
  def run
    if ENV['SERVICE_DOWN'] == 'true'
      raise "Service unavailable"
    end
    @data = { users: 100, orders: 50 }
  end
end

class FallbackService < Taski::Task
  exports :cached_data
  
  def run
    @cached_data = { users: 90, orders: 45 }  # Slightly stale data
  end
end

class ReliableConsumer < Taski::Task
  # Rescue any StandardError from dependencies
  rescue_deps StandardError, -> { FallbackService.cached_data }
  
  def run
    data = UnreliableService.data
    puts "Processing data: #{data}"
  end
end

# Test normal operation
ENV['SERVICE_DOWN'] = 'false'
ReliableConsumer.run
# => Processing data: {users: 100, orders: 50}

# Test fallback
ENV['SERVICE_DOWN'] = 'true'
ReliableConsumer.reset!
ReliableConsumer.run
# => Processing data: {users: 90, orders: 45}
```

### Multiple Rescue Strategies

```ruby
class PrimaryAPI < Taski::Task
  exports :api_data
  
  def run
    raise "Primary API down" if ENV['PRIMARY_DOWN'] == 'true'
    @api_data = { source: 'primary', data: 'fresh' }
  end
end

class SecondaryAPI < Taski::Task
  exports :backup_data
  
  def run
    raise "Secondary API down" if ENV['SECONDARY_DOWN'] == 'true'
    @backup_data = { source: 'secondary', data: 'good' }
  end
end

class LocalCache < Taski::Task
  exports :cached_data
  
  def run
    raise "Cache corrupted" if ENV['CACHE_CORRUPTED'] == 'true'
    @cached_data = { source: 'cache', data: 'stale' }
  end
end

class ResilientDataProcessor < Taski::Task
  # Try primary API first
  rescue_deps StandardError, -> { SecondaryAPI.backup_data }
  # If that fails, try local cache
  rescue_deps StandardError, -> { LocalCache.cached_data }
  # If all else fails, use static data
  rescue_deps StandardError, -> { { source: 'static', data: 'default' } }
  
  def run
    data = PrimaryAPI.api_data
    puts "Using data from #{data[:source]}: #{data[:data]}"
  end
end

# Test various failure scenarios
ENV['PRIMARY_DOWN'] = 'true'
ResilientDataProcessor.run
# => Using data from secondary: good

ENV['SECONDARY_DOWN'] = 'true'
ResilientDataProcessor.reset!
ResilientDataProcessor.run
# => Using data from cache: stale

ENV['CACHE_CORRUPTED'] = 'true'
ResilientDataProcessor.reset!
ResilientDataProcessor.run
# => Using data from static: default
```

### Conditional Error Recovery

```ruby
class ExternalService < Taski::Task
  exports :external_data
  
  def run
    case ENV['ERROR_TYPE']
    when 'network'
      raise SocketError, "Network unreachable"
    when 'timeout'
      raise Timeout::Error, "Request timed out"
    when 'auth'
      raise SecurityError, "Authentication failed"
    else
      @external_data = "external service data"
    end
  end
end

class SmartConsumer < Taski::Task
  # Only rescue network and timeout errors, not auth errors
  rescue_deps SocketError, Timeout::Error, -> { "fallback data" }
  
  def run
    data = ExternalService.external_data
    puts "Using: #{data}"
  end
end

# Network error - rescued
ENV['ERROR_TYPE'] = 'network'
SmartConsumer.run
# => Using: fallback data

# Auth error - not rescued, propagates up
ENV['ERROR_TYPE'] = 'auth'
begin
  SmartConsumer.reset!
  SmartConsumer.run
rescue Taski::TaskBuildError => e
  puts "Auth error not handled: #{e.cause.message}"
end
# => Auth error not handled: Authentication failed
```

## Error Recovery Patterns

### Circuit Breaker Pattern

```ruby
class CircuitBreakerService < Taski::Task
  exports :service_data
  
  def run
    failure_count = ENV['FAILURE_COUNT'].to_i
    
    if failure_count >= 3
      raise "Circuit breaker open - too many failures"
    end
    
    @service_data = "service response"
  end
end

class CircuitBreakerConsumer < Taski::Task
  rescue_deps StandardError, -> { 
    puts "Circuit breaker activated, using cached response"
    "cached response" 
  }
  
  def run
    data = CircuitBreakerService.service_data
    puts "Service response: #{data}"
  end
end

ENV['FAILURE_COUNT'] = '5'
CircuitBreakerConsumer.run
# => Circuit breaker activated, using cached response
```

### Retry with Backoff

```ruby
class RetryableService < Taski::Task
  exports :retry_data
  
  def run
    attempt = (ENV['ATTEMPT'] || '1').to_i
    
    if attempt < 3
      ENV['ATTEMPT'] = (attempt + 1).to_s
      raise "Temporary failure (attempt #{attempt})"
    end
    
    @retry_data = "success on attempt #{attempt}"
  end
end

class RetryingConsumer < Taski::Task
  rescue_deps StandardError, -> {
    puts "Retrying after failure..."
    sleep(1)  # Simple backoff
    RetryableService.reset!
    
    begin
      RetryableService.retry_data
    rescue => e
      "final fallback after retries"
    end
  }
  
  def run
    data = RetryableService.retry_data
    puts "Final result: #{data}"
  end
end

ENV['ATTEMPT'] = '1'
RetryingConsumer.run
# => Retrying after failure...
# => Final result: success on attempt 3
```

## Static Analysis Errors

Taski performs static analysis to detect dependency issues early.

### Missing Dependencies

```ruby
class MissingDepTask < Taski::Task
  exports :result
  
  def run
    # This will cause a NameError at class definition time
    @result = UndefinedTask.some_value
  end
end

# Error occurs immediately when class is defined:
# NameError: uninitialized constant UndefinedTask
```

### Invalid ref() Usage

```ruby
class InvalidRefTask < Taski::Task
  define :invalid_ref, -> {
    ref("NonExistentTask").value  # Will fail at runtime
  }
  
  def run
    puts invalid_ref
  end
end

begin
  InvalidRefTask.run
rescue => e
  puts "Reference error: #{e.message}"
end
# => Reference error: uninitialized constant NonExistentTask
```

## Signal Interruption Handling

Handle task interruption gracefully with proper cleanup.

### Basic Signal Handling

```ruby
class InterruptibleTask < Taski::Task
  def run
    puts "Starting long operation..."
    
    begin
      long_running_operation
    rescue Taski::TaskInterruptedException => e
      puts "Task interrupted: #{e.message}"
      perform_cleanup
      raise  # Re-raise to maintain proper error flow
    end
    
    puts "Operation completed"
  end
  
  private
  
  def long_running_operation
    50.times do |i|
      puts "Step #{i + 1}/50"
      sleep(0.2)
    end
  end
  
  def perform_cleanup
    puts "Cleaning up resources..."
    puts "Cleanup complete"
  end
end

# Run with Ctrl+C to test interruption
InterruptibleTask.run
```

### Nested Task Interruption

```ruby
class DatabaseMigration < Taski::Task
  def run
    puts "Starting migration..."
    
    begin
      migrate_schema
      migrate_data
    rescue Taski::TaskInterruptedException => e
      puts "Migration interrupted, rolling back..."
      rollback_changes
      raise
    end
    
    puts "Migration completed"
  end
  
  private
  
  def migrate_schema
    puts "Migrating schema..."
    sleep(2)
  end
  
  def migrate_data
    puts "Migrating data..."
    sleep(3)
  end
  
  def rollback_changes
    puts "Rolling back migration changes..."
    sleep(1)
  end
end
```

## Debugging Strategies

### Comprehensive Error Logging

```ruby
class DiagnosticTask < Taski::Task
  def run
    begin
      risky_operation
    rescue => e
      Taski.logger.error "Task failed", 
                         task: self.class.name,
                         error_class: e.class.name,
                         error_message: e.message,
                         backtrace: e.backtrace.first(5)
      raise
    end
  end
  
  private
  
  def risky_operation
    raise "Diagnostic error for testing"
  end
end
```

### Dependency Chain Analysis

```ruby
class DebugTask < Taski::Task
  exports :debug_info
  
  def run
    puts "Dependency analysis:"
    puts "  Dependencies: #{self.class.dependencies.map(&:name)}"
    puts "  Dependency tree:"
    puts self.class.tree.split("\n").map { |line| "    #{line}" }
    
    @debug_info = "debug complete"
  end
end
```

## Best Practices

### 1. Fail Fast and Clearly

```ruby
# ✅ Good: Clear error messages
class ValidatingTask < Taski::Task
  def run
    validate_environment!
    perform_work
  end
  
  private
  
  def validate_environment!
    required_vars = %w[DATABASE_URL API_KEY]
    missing = required_vars.select { |var| ENV[var].nil? || ENV[var].empty? }
    
    if missing.any?
      raise "Missing required environment variables: #{missing.join(', ')}"
    end
  end
end
```

### 2. Provide Meaningful Fallbacks

```ruby
# ✅ Good: Meaningful fallback with logging
class GracefulTask < Taski::Task
  rescue_deps StandardError, -> {
    Taski.logger.warn "Primary service failed, using fallback"
    load_fallback_data
  }
  
  def self.load_fallback_data
    { status: 'degraded', message: 'Using cached data due to service outage' }
  end
end
```

### 3. Test Error Scenarios

```ruby
# Test both success and failure paths
class TestableTask < Taski::Task
  exports :result
  
  def run
    if ENV['SIMULATE_FAILURE'] == 'true'
      raise "Simulated failure for testing"
    end
    
    @result = "success"
  end
end

# In tests:
# ENV['SIMULATE_FAILURE'] = 'true'
# expect { TestableTask.run }.to raise_error(Taski::TaskBuildError)
```

This comprehensive error handling guide ensures your Taski applications are robust and maintainable in production environments.