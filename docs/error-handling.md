# Error Handling Guide

This guide covers Taski's comprehensive error handling capabilities including parallel task errors, task-specific error classes, and error recovery strategies.

## Error Types

Taski provides specific exception types for different error scenarios:

- `Taski::AggregateError`: Multiple tasks failed during parallel execution
- `Taski::TaskError`: Base class for task-specific errors
- `Taski::TaskAbortException`: Intentional task abort (propagates immediately)
- `Taski::CircularDependencyError`: Circular dependency detected
- `TaskClass::Error`: Auto-generated error class for each Task subclass

## AggregateError for Parallel Execution

When multiple tasks fail during parallel execution, Taski wraps all errors into an `AggregateError`.

### Basic Error Handling

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
    raise "Cache connection failed"
  end
end

class ApplicationTask < Taski::Task
  exports :result

  def run
    # Both dependencies are executed in parallel
    db = DatabaseTask.connection
    cache = CacheTask.redis_client
    @result = "App started"
  end
end

begin
  ApplicationTask.run
rescue Taski::AggregateError => e
  puts "#{e.errors.size} tasks failed:"
  e.errors.each do |failure|
    puts "  - #{failure.task_class.name}: #{failure.error.message}"
  end
end

# Output:
# 2 tasks failed:
#   - DatabaseTask: Database connection failed
#   - CacheTask: Cache connection failed
```

### Accessing Individual Errors

```ruby
begin
  ApplicationTask.run
rescue Taski::AggregateError => e
  # Access all errors
  e.errors.each do |failure|
    puts "Task: #{failure.task_class}"
    puts "Error: #{failure.error.class} - #{failure.error.message}"
  end

  # Check for specific error types
  if e.includes?(Timeout::Error)
    puts "Some tasks timed out"
  end

  # Get the first error (for backward compatibility with cause chain)
  puts "First error: #{e.cause.message}"
end
```

## Task-Specific Error Classes

Each Task subclass automatically gets an `::Error` class that allows rescuing errors by task.

### Auto-Generated Error Classes

```ruby
class MyTask < Taski::Task
  exports :result

  def run
    raise "Something went wrong"
  end
end

# MyTask::Error is automatically defined and inherits from Taski::TaskError
puts MyTask::Error.ancestors
# => [MyTask::Error, Taski::TaskError, StandardError, ...]
```

### Rescuing by Task Class

```ruby
class DatabaseTask < Taski::Task
  exports :connection

  def run
    raise "Connection failed"
  end
end

class ApplicationTask < Taski::Task
  exports :result

  def run
    @result = DatabaseTask.connection
  end
end

# Rescue errors from a specific task
begin
  ApplicationTask.run
rescue DatabaseTask::Error => e
  puts "Database task failed: #{e.message}"
  puts "Original error: #{e.cause.class}"
  puts "Task class: #{e.task_class}"
end
```

### How It Works

When you use `rescue DatabaseTask::Error`, it will match an `AggregateError` that contains a `DatabaseTask::Error`. This is possible because:

1. Each `TaskClass::Error` extends `Taski::AggregateAware`
2. `AggregateAware` overrides the `===` operator used by `rescue`
3. When rescue checks `DatabaseTask::Error === aggregate_error`, it returns true if the aggregate contains that error type

```ruby
# This works transparently:
begin
  ApplicationTask.run
rescue DatabaseTask::Error => e
  # e is actually a Taski::AggregateError, but rescue matches it
  # because AggregateError contains DatabaseTask::Error
  puts e.class  # => Taski::AggregateError
end
```

## AggregateAware for Custom Exceptions

You can extend your own exception classes with `AggregateAware` to enable the same transparent rescue matching.

```ruby
class MyCustomError < StandardError
  extend Taski::AggregateAware
end

class FailingTask < Taski::Task
  exports :result

  def run
    raise MyCustomError, "Custom failure"
  end
end

class ParentTask < Taski::Task
  exports :result

  def run
    @result = FailingTask.result
  end
end

# MyCustomError will match AggregateError containing MyCustomError
begin
  ParentTask.run
rescue MyCustomError => e
  puts "Caught via AggregateAware: #{e.message}"
end
```

## Circular Dependency Detection

Taski automatically detects circular dependencies before execution.

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
  puts "Cyclic tasks: #{e.cyclic_tasks}"
end

# Output:
# Error: Circular dependency detected: TaskA <-> TaskB
# Cyclic tasks: [[TaskA, TaskB]]
```

## Task Abort

Use `TaskAbortException` to immediately stop all task execution.

```ruby
class CriticalTask < Taski::Task
  exports :result

  def run
    if critical_condition_met?
      raise Taski::TaskAbortException, "Critical condition - aborting all tasks"
    end
    @result = "completed"
  end
end

begin
  CriticalTask.run
rescue Taski::TaskAbortException => e
  puts "Execution aborted: #{e.message}"
  # Clean up resources, notify monitoring, etc.
end
```

`TaskAbortException` takes priority over regular errors. If both abort and regular errors occur during parallel execution, only `TaskAbortException` is raised.

## Error Deduplication

When the same error propagates through multiple dependency paths, Taski automatically deduplicates it.

```ruby
class SharedDependency < Taski::Task
  exports :value

  def run
    raise "Shared dependency failed"
  end
end

class TaskA < Taski::Task
  exports :a

  def run
    @a = SharedDependency.value
  end
end

class TaskB < Taski::Task
  exports :b

  def run
    @b = SharedDependency.value
  end
end

class RootTask < Taski::Task
  exports :result

  def run
    @result = "#{TaskA.a} and #{TaskB.b}"
  end
end

begin
  RootTask.run
rescue Taski::AggregateError => e
  # Only 1 error, not 2 - the shared dependency error is deduplicated
  puts "#{e.errors.size} error(s)"  # => "1 error(s)"
end
```

## Best Practices

### 1. Handle Errors at the Right Level

```ruby
# Good: Handle errors within the task that knows how to recover
class ResilientTask < Taski::Task
  exports :data

  def run
    @data = fetch_from_primary_source
  rescue Timeout::Error
    @data = fetch_from_fallback
  end
end

# The task's responsibility is to provide data, and it handles
# its own recovery strategy internally
```

### 2. Use Task-Specific Errors for Clarity

```ruby
# Clear which task failed
begin
  ApplicationTask.run
rescue DatabaseTask::Error => e
  handle_database_failure(e)
rescue CacheTask::Error => e
  handle_cache_failure(e)
end
```

### 3. Fail Fast with Clear Messages

```ruby
class ValidatingTask < Taski::Task
  exports :config

  def run
    validate_environment!
    @config = load_config
  end

  private

  def validate_environment!
    missing = %w[DATABASE_URL API_KEY].select { |var| ENV[var].nil? }
    if missing.any?
      raise "Missing required environment variables: #{missing.join(', ')}"
    end
  end
end
```

### 4. Use Abort for Unrecoverable Situations

```ruby
class SafetyCheckTask < Taski::Task
  exports :result

  def run
    if system_compromised?
      raise Taski::TaskAbortException, "Security violation detected"
    end
    @result = perform_operation
  end
end
```

## Debugging Tips

### Visualize Dependencies

```ruby
# Print the dependency tree before execution
puts MyTask.tree

# Output:
# MyTask
# ├── DatabaseTask
# └── CacheTask
#     └── ConfigTask
```

### Enable Debug Logging

```bash
TASKI_DEBUG=1 ruby my_script.rb
```

This enables detailed logging of task execution, including dependency resolution and error propagation.
