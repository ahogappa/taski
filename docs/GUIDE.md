# Taski Guide

This guide provides detailed documentation beyond the basics covered in the README.

## Table of Contents

- [Error Handling](#error-handling)
- [Lifecycle Management](#lifecycle-management)
- [Progress Display](#progress-display)
- [Debugging](#debugging)

---

## Error Handling

Taski provides comprehensive error handling for parallel task execution.

### Error Types

| Exception | Purpose |
|-----------|---------|
| `Taski::AggregateError` | Multiple tasks failed during parallel execution |
| `Taski::TaskError` | Base class for task-specific errors |
| `Taski::TaskAbortException` | Intentional abort (stops all tasks immediately) |
| `Taski::CircularDependencyError` | Circular dependency detected |
| `TaskClass::Error` | Auto-generated error class for each Task subclass |

### AggregateError

When multiple tasks fail during parallel execution, errors are collected into an `AggregateError`:

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

class AppTask < Taski::Task
  def run
    db = DatabaseTask.connection
    cache = CacheTask.redis_client
  end
end

begin
  AppTask.run
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

### Task-Specific Error Classes

Each Task subclass automatically gets an `::Error` class for targeted rescue:

```ruby
class DatabaseTask < Taski::Task
  exports :connection
  def run
    raise "Connection failed"
  end
end

# Rescue errors from a specific task
begin
  AppTask.run
rescue DatabaseTask::Error => e
  puts "Database task failed: #{e.message}"
  # e.task_class returns DatabaseTask
  # e.cause returns the original error
end
```

This works transparently with `AggregateError` - when you rescue `DatabaseTask::Error`, it matches an `AggregateError` that contains a `DatabaseTask::Error`.

### TaskAbortException

Use `TaskAbortException` to immediately stop all task execution:

```ruby
class CriticalTask < Taski::Task
  def run
    if critical_condition_met?
      raise Taski::TaskAbortException, "Critical error - aborting"
    end
  end
end
```

`TaskAbortException` takes priority over regular errors. Already running tasks will complete, but no new tasks will start.

### Error Handling Best Practices

```ruby
# 1. Handle errors within the task when recovery is possible
class ResilientTask < Taski::Task
  exports :data
  def run
    @data = fetch_from_primary
  rescue Timeout::Error
    @data = fetch_from_fallback
  end
end

# 2. Use task-specific errors for clarity
begin
  AppTask.run
rescue DatabaseTask::Error => e
  handle_database_failure(e)
rescue CacheTask::Error => e
  handle_cache_failure(e)
end

# 3. Fail fast with clear messages
class ValidatingTask < Taski::Task
  def run
    missing = %w[DATABASE_URL API_KEY].select { |v| ENV[v].nil? }
    raise "Missing: #{missing.join(', ')}" if missing.any?
  end
end
```

---

## Lifecycle Management

Taski supports resource cleanup with `run`, `clean`, and `run_and_clean` methods.

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
  end
end

class WebServer < Taski::Task
  def run
    puts "Server started with #{DatabaseSetup.connection}"
  end

  def clean
    puts "Server stopped"
  end
end

# Start
WebServer.run
# => Database connected
# => Server started with postgresql://localhost:5432/myapp

# Clean (reverse dependency order)
WebServer.clean
# => Server stopped
# => Database disconnected
```

### run_and_clean

Execute run followed by clean in a single operation:

```ruby
WebServer.run_and_clean
# => Database connected
# => Server started
# => Server stopped
# => Database disconnected
```

### Idempotent Clean Methods

Clean methods should be safe to call multiple times:

```ruby
class SafeFileTask < Taski::Task
  exports :data_file

  def run
    @data_file = '/tmp/data.txt'
    File.write(@data_file, 'data')
  end

  def clean
    # Check before delete
    if @data_file && File.exist?(@data_file)
      File.delete(@data_file)
    end
  end
end
```

---

## Progress Display

Taski provides real-time progress visualization during task execution.

### Features

- **Spinner Animation**: Animated spinner during execution
- **Output Capture**: Real-time display of task output (last line)
- **Status Indicators**: Success/failure icons with execution time
- **Group Blocks**: Organize output messages into logical phases
- **TTY Detection**: Clean output when redirected to files

### Group Blocks

Use `group` blocks to organize output within a task into logical phases. The current group name is displayed alongside the task's output in the progress display.

```ruby
class DeployTask < Taski::Task
  def run
    group("Preparing environment") do
      puts "Checking dependencies..."
      puts "Validating config..."
    end

    group("Building application") do
      puts "Compiling source..."
      puts "Running tests..."
    end

    group("Deploying") do
      puts "Uploading files..."
      puts "Restarting server..."
    end
  end
end
```

Progress display output:

```
During execution:
⠋ DeployTask (Task) | Deploying: Uploading files...

After completion:
✓ DeployTask (Task) 520ms
```

The group name appears as a prefix to the output message: `| GroupName: output...`

Groups are useful for:
- **Logical organization**: Group related operations together
- **Progress visibility**: See which phase is currently executing
- **Error context**: Know which phase failed when errors occur

### Example Output

```
During execution:
  WebServer (Task)
  ├── Config (Task) ...
  │   ├── Database (Task) 45.2ms
  │   └── Cache (Task) ...
  └── Server (Task)

After completion:
  WebServer (Task) 120.5ms
  ├── Config (Task) 50.3ms
  │   ├── Database (Task) 45.2ms
  │   └── Cache (Task) 48.1ms
  └── Server (Task) 70.2ms
```

### Disabling Progress Display

```bash
TASKI_PROGRESS_DISABLE=1 ruby your_script.rb
```

### File Output Mode

When output is redirected, interactive spinners are automatically disabled:

```bash
ruby build.rb > build.log 2>&1
```

---

## Debugging

### Environment Variables

| Variable | Purpose |
|----------|---------|
| `TASKI_PROGRESS_DISABLE=1` | Disable progress display |
| `TASKI_DEBUG=1` | Enable debug output |

### Dependency Tree Visualization

```ruby
puts MyTask.tree
# MyTask (Task)
# ├── DatabaseTask (Task)
# └── CacheTask (Task)
#     └── ConfigTask (Task)
```

### Common Issues

**Circular Dependencies**

```ruby
# Detected before execution
begin
  TaskA.run
rescue Taski::CircularDependencyError => e
  puts e.cyclic_tasks  # [[TaskA, TaskB]]
end
```

**Static Analysis Requirements**

Tasks must be defined in source files (not dynamically with `Class.new`) because static analysis uses Prism AST parsing which requires actual source files.
