# Taski

[![CI](https://github.com/ahogappa/taski/workflows/CI/badge.svg)](https://github.com/ahogappa/taski/actions/workflows/ci.yml)
[![Codecov](https://codecov.io/gh/ahogappa/taski/branch/master/graph/badge.svg)](https://codecov.io/gh/ahogappa/taski)
[![Gem Version](https://badge.fury.io/rb/taski.svg)](https://badge.fury.io/rb/taski)

> **🚧 Development Status:** Taski is currently under active development. Not yet recommended for production use.

**Taski** is a Ruby framework for building task dependency graphs with automatic resolution and execution. It provides three APIs: static dependencies through **Exports**, dynamic dependencies through **Define**, and abstraction layers through **Section**.

> **Name Origin**: "Taski" comes from the Japanese word "襷" (tasuki), a sash used in relay races. Just like how runners pass the sash to the next teammate, tasks in Taski pass dependencies to one another in a continuous chain.

## 🚀 Quick Start

```ruby
require 'taski'

# Static dependency using Exports API
class DatabaseSetup < Taski::Task
  exports :connection_string

  def run
    @connection_string = "postgresql://localhost/myapp"
    puts "Database configured"
  end
end

class APIServer < Taski::Task
  def run
    puts "Starting API with #{DatabaseSetup.connection_string}"
  end
end

APIServer.run  # You can also use APIServer.build for compatibility
# => Database configured
# => Starting API with postgresql://localhost/myapp
```

## 📚 API Guide

### Exports API - Static Dependencies

For simple, predictable dependencies:

```ruby
class ConfigLoader < Taski::Task
  exports :app_name, :version

  def run
    @app_name = "MyApp"
    @version = "1.0.0"
    puts "Config loaded: #{@app_name} v#{@version}"
  end
end

class Deployment < Taski::Task
  def run
    @deploy_url = "https://#{ConfigLoader.app_name}.example.com"
    puts "Deploying to #{@deploy_url}"
  end
end

Deployment.run
# => Config loaded: MyApp v1.0.0
# => Deploying to https://MyApp.example.com
```

### Define API - Dynamic Dependencies

For dependencies that change based on runtime conditions:

```ruby
class EnvironmentConfig < Taski::Task
  define :database_service, -> {
    case ENV['RAILS_ENV']
    when 'production'
      "production-db.example.com"
    else
      "localhost:5432"
    end
  }

  def run
    puts "Using database: #{database_service}"
    puts "Environment: #{ENV['RAILS_ENV'] || 'development'}"
  end
end

EnvironmentConfig.run
# => Using database: localhost:5432
# => Environment: development

ENV['RAILS_ENV'] = 'production'
EnvironmentConfig.reset!
EnvironmentConfig.run
# => Using database: production-db.example.com
# => Environment: production
```

### Section API - Abstraction Layers

For environment-specific implementations with clean interfaces:

```ruby
class DatabaseSection < Taski::Section
  interface :host, :port

  def impl
    ENV['RAILS_ENV'] == 'production' ? Production : Development
  end

  class Production < Taski::Task
    def run
      @host = "prod-db.example.com"
      @port = 5432
    end
  end

  class Development < Taski::Task
    def run
      @host = "localhost"
      @port = 5432
    end
  end
end

# Usage is simple - Section works like any Task
class App < Taski::Task
  def run
    puts "DB: #{DatabaseSection.host}:#{DatabaseSection.port}"
  end
end

App.run  # => DB: localhost:5432
```

### When to Use Each API

- **Define API**: Best for dynamic runtime dependencies. Cannot contain side effects in definition blocks. Dependencies are analyzed at class definition time, not runtime.
- **Exports API**: Ideal for static dependencies. Supports side effects in run methods.
- **Section API**: Perfect for abstraction layers where you need different implementations based on runtime conditions while maintaining static analysis capabilities.

| Use Case | API | Example |
|----------|-----|---------|
| Configuration values | Exports | File paths, settings |
| Environment-specific logic | Define/Section | Different services per env |
| Side effects | Exports | Database connections, I/O |
| Conditional processing | Define | Algorithm selection |
| Implementation abstraction | Section | Database/API adapters |
| Multi-environment configs | Section | Dev/Test/Prod settings |

**Note**: Define API analyzes dependencies when the class is defined. Conditional dependencies like `ENV['USE_NEW'] ? TaskA : TaskB` will only include the task selected at class definition time, not runtime. Use Section API when you need true runtime selection.

### ref() Method

The `ref()` method enables forward declarations in Define API:

```ruby
class TaskA < Taski::Task
  define :result, -> { ref("TaskB").value }
end

class TaskB < Taski::Task
  exports :value
  def run
    @value = "B result"
  end
end
```

**⚠️ Important**: ref() cannot detect circular references at definition time. Use direct references when possible:

```ruby
# ✅ Preferred
define :result, -> { TaskB.value }

# ⚠️ Only when forward declaration needed
define :result, -> { ref("TaskB").value }
```

## ✨ Key Features

- **Automatic Dependency Resolution**: Dependencies detected through static analysis
- **Thread-Safe**: Safe for concurrent access
- **Circular Dependency Detection**: Clear error messages with detailed paths
- **Granular Execution**: Build individual tasks or complete graphs
- **Memory Management**: Built-in reset mechanisms
- **Progress Display**: Visual feedback with spinners and output capture
- **Dependency Tree Visualization**: Visual representation of task relationships

### Dependency Tree Visualization

Visualize task dependencies with the `tree` method:

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

# Sections also appear in dependency trees
puts AppServer.tree
# => AppServer
# => └── DatabaseSection
```

### Progress Display

Taski provides visual feedback during task execution with animated spinners and real-time output capture:

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

**Progress Display Features:**
- **Spinner Animation**: Dots-style spinner during task execution
- **Output Capture**: Real-time display of task output (last 5 lines)
- **Status Indicators**: ✅ for success, ❌ for failure
- **Execution Time**: Shows task duration after completion
- **TTY Detection**: Clean output when redirected to files

### Granular Task Execution

Execute any task individually - Taski builds only required dependencies:

```ruby
# Run specific components
ConfigLoader.run           # Runs only ConfigLoader
# => Config loaded: MyApp v1.0.0

EnvironmentConfig.run      # Runs EnvironmentConfig and its dependencies
# => Using database: localhost:5432
# => Environment: development

# Access values (triggers execution if needed)
puts ConfigLoader.version    # Runs ConfigLoader if not executed
# => 1.0.0
```

### Lifecycle Management

Tasks can define both run and clean methods. Clean operations run in reverse dependency order:

```ruby
class DatabaseSetup < Taski::Task
  exports :connection

  def run
    @connection = "db-connection"
    puts "Database connected"
  end

  def clean
    puts "Database disconnected"
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

WebServer.run
# => Database connected
# => Web server started with db-connection

WebServer.clean
# => Web server stopped
# => Database disconnected
```

### Clean Method Idempotency

**Important**: The `clean` method must be idempotent - safe to call multiple times without errors.

```ruby
class FileTask < Taski::Task
  exports :output_file

  def run
    @output_file = '/tmp/data.csv'
    File.write(@output_file, process_data)
  end

  def clean
    # ❌ Bad: Raises error if file doesn't exist
    # File.delete(@output_file)

    # ✅ Good: Check before delete
    File.delete(@output_file) if File.exist?(@output_file)
  end
end
```

### Error Handling

```ruby
begin
  TaskWithCircularDep.run
rescue Taski::CircularDependencyError => e
  puts "Circular dependency: #{e.message}"
end
# => Circular dependency: Circular dependency detected!
# => Cycle: TaskA → TaskB → TaskA
# =>
# => The dependency chain is:
# =>   1. TaskA is trying to build → TaskB
# =>   2. TaskB is trying to build → TaskA
```

### Dependency Resolution Phases

Taski resolves dependencies in three distinct phases, each with specific error detection capabilities:

| Phase | Timing | Dependencies Resolved | Common Errors |
|-------|--------|----------------------|---------------|
| **Phase 1: Definition Time** | Class loading | Exports API static analysis | Missing method definitions, syntax errors |
| **Phase 2: Pre-execution** | Before `.run()` call | Define API ref() validation, dependency graph | Circular dependencies, missing ref() targets |
| **Phase 3: Execution** | During `.run()` call | Runtime method calls | Runtime failures, runtime exceptions |

```ruby
# Phase 1: Static analysis errors (at class definition)
class BadTask < Taski::Task
  exports :value
  def run
    @value = UndefinedTask.value  # ❌ Detected immediately
  end
end

# Phase 2: Reference validation errors (before execution)
class RefTask < Taski::Task
  define :result, -> { ref("NonExistentTask").value }  # ❌ Detected at .run()
end

# Phase 3: Runtime errors (during execution)
class RuntimeTask < Taski::Task
  def run
    raise "Task failed"  # ❌ Detected during task execution
  end
end
```

## 📦 Installation

```ruby
gem 'taski'
```

```bash
bundle install
```

## 🧪 Testing

```bash
bundle exec rake test
```

## 🏛️ Architecture

- **Task Base**: Core framework
- **Exports API**: Static dependency resolution
- **Define API**: Dynamic dependency resolution
- **Section API**: Abstraction layer with runtime implementation selection
- **Instance Management**: Thread-safe lifecycle
- **Dependency Resolver**: Topological sorting with Section support

## Contributing

Bug reports and pull requests welcome at https://github.com/ahogappa/taski.

## License

MIT License

---

**Taski** - Build dependency graphs with elegant Ruby code. 🚀
