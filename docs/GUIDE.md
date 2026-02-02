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

```text
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

### Display Modes

Taski supports two progress display modes:

#### Tree Mode (Default)

Full dependency tree visualization with status for each task:

```
WebServer (Task)
├── ⠋ Config (Task) | Reading config.yml...
│   ├── ✅ Database (Task) 45.2ms
│   └── ⠙ Cache (Task) | Connecting...
└── ◻ Server (Task)
```

#### Simple Mode

Compact single-line display showing current progress:

```
⠹ [3/5] DeployTask | Uploading files...
✓ [5/5] All tasks completed (1234ms)
```

Format: `[spinner] [completed/total] TaskName | last output...`

When multiple tasks run in parallel:
```
⠹ [2/5] DownloadLayer1, DownloadLayer2 | Downloading...
```

On failure:
```
✗ [3/5] DeployTask failed: Connection refused
```

#### Plain Mode

Plain text output without escape codes, designed for CI/logs:

```
[START] DatabaseSetup
[DONE] DatabaseSetup (45.2ms)
[START] WebServer
[DONE] WebServer (120.5ms)
[TASKI] Completed: 2/2 tasks (165ms)
```

### Configuring Progress Mode

**Via API:**

```ruby
Taski.progress_mode = :tree    # Tree display (default)
Taski.progress_mode = :simple  # Single-line display
Taski.progress_mode = :plain   # Plain text (CI/logs)
```

**Via environment variable:**

```bash
TASKI_PROGRESS_MODE=tree ruby your_script.rb
TASKI_PROGRESS_MODE=simple ruby your_script.rb
TASKI_PROGRESS_MODE=plain ruby your_script.rb
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

### Custom Progress Display

Taski provides two layers of customization for progress displays:

1. **ProgressEventSubscriber** - Simple callback-based API for lightweight use cases
2. **ProgressFeatures modules** - Reusable components for building full custom displays

#### Layer 1: ProgressEventSubscriber

Perfect for logging, notifications, or webhooks. Just register callbacks for the events you care about:

```ruby
logger = Taski::Execution::ProgressEventSubscriber.new do |events|
  events.on_execution_start { puts "Execution started" }
  events.on_execution_stop { puts "Execution completed" }

  events.on_task_start { |task, _| puts "[START] #{task.name}" }
  events.on_task_complete { |task, info| puts "[DONE] #{task.name} (#{info[:duration]}ms)" }
  events.on_task_fail { |task, info| puts "[FAIL] #{task.name}: #{info[:error]}" }

  events.on_progress do |summary|
    percent = (summary[:completed].to_f / summary[:total] * 100).round(0)
    puts "Progress: #{percent}%"
  end
end

# Add as observer to ExecutionContext
context = Taski::Execution::ExecutionContext.new
context.add_observer(logger)

old_context = Taski::Execution::ExecutionContext.current
begin
  Taski::Execution::ExecutionContext.current = context
  MyTask.run
ensure
  Taski::Execution::ExecutionContext.current = old_context
end
```

**Available callbacks:**

| Callback | Arguments | When called |
|----------|-----------|-------------|
| `on_execution_start` | none | Execution begins |
| `on_execution_stop` | none | Execution ends |
| `on_task_start` | `task_class, info` | Task starts running |
| `on_task_complete` | `task_class, info` | Task completes successfully |
| `on_task_fail` | `task_class, info` | Task fails with error |
| `on_task_skip` | `task_class, info` | Task is skipped |
| `on_task_cleaning` | `task_class, info` | Task cleanup starts |
| `on_task_clean_complete` | `task_class, info` | Task cleanup completes |
| `on_task_clean_fail` | `task_class, info` | Task cleanup fails |
| `on_group_start` | `task_class, group_name` | Group block starts |
| `on_group_complete` | `task_class, group_name, info` | Group block ends |
| `on_progress` | `summary` | Task state changes |

The `info` hash contains `:duration` (milliseconds) and `:error` (Exception) when applicable.
The `summary` hash contains `:completed`, `:total`, `:running` (array), and `:failed` (array).

#### Layer 2: ProgressFeatures Modules

For full custom displays, mix in these reusable modules:

```ruby
class MyProgressDisplay
  include Taski::Execution::ProgressFeatures::SpinnerAnimation
  include Taski::Execution::ProgressFeatures::TerminalControl
  include Taski::Execution::ProgressFeatures::Formatting
  include Taski::Execution::ProgressFeatures::ProgressTracking

  def initialize(output: $stdout)
    @output = output
    init_progress_tracking
  end

  def start
    hide_cursor
    start_spinner(frames: %w[- \\ | /], interval: 0.1) { render }
  end

  def stop
    stop_spinner
    show_cursor
    render_final
  end

  def update_task(task_class, state:, duration: nil, error: nil)
    register_task(task_class)
    update_task_state(task_class, state, duration, error)
  end

  private

  def render
    summary = progress_summary
    line = "#{current_frame} [#{summary[:completed]}/#{summary[:total]}]"
    clear_line
    @output.print line
  end

  def render_final
    summary = progress_summary
    @output.puts "\nCompleted: #{summary[:completed]}/#{summary[:total]} tasks"
  end
end
```

**Available modules:**

| Module | Purpose |
|--------|---------|
| `SpinnerAnimation` | `start_spinner`, `stop_spinner`, `current_frame` |
| `TerminalControl` | `hide_cursor`, `show_cursor`, `clear_line`, `tty?`, `terminal_width` |
| `AnsiColors` | `colorize(text, :red, :bold)`, `status_color(:completed)` |
| `Formatting` | `short_name(task_class)`, `format_duration(ms)`, `truncate(text, len)` |
| `TreeRendering` | `each_tree_node(tree)`, `tree_prefix(depth, is_last)` |
| `ProgressTracking` | `register_task`, `update_task_state`, `progress_summary` |

See `examples/custom_progress_demo.rb` for complete working examples.

---

## Debugging

### Environment Variables

| Variable | Purpose |
|----------|---------|
| `TASKI_PROGRESS_DISABLE=1` | Disable progress display |
| `TASKI_PROGRESS_MODE=tree\|simple\|plain` | Set progress display mode (default: tree) |
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
