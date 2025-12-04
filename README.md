# Taski

[![CI](https://github.com/ahogappa/taski/workflows/CI/badge.svg)](https://github.com/ahogappa/taski/actions/workflows/ci.yml)
[![Codecov](https://codecov.io/gh/ahogappa/taski/branch/master/graph/badge.svg)](https://codecov.io/gh/ahogappa/taski)
[![Gem Version](https://badge.fury.io/rb/taski.svg)](https://badge.fury.io/rb/taski)

> **🚧 Development Status:** Taski is currently under active development. Not yet recommended for production use.

**Taski** is a Ruby framework for building task dependency graphs with automatic resolution and **parallel execution**.

> **Name Origin**: "Taski" comes from the Japanese word "襷" (tasuki), a sash used in relay races. Just like how runners pass the sash to the next teammate, tasks in Taski pass dependencies to one another in a continuous chain.

## Why Taski?

Build complex workflows by defining tasks and their dependencies - Taski automatically resolves execution order and executes them in parallel.

- **Automatic Dependency Resolution**: Dependencies detected via static analysis
- **Parallel Execution**: Independent tasks run concurrently for maximum performance
- **Two Simple APIs**: Exports (value sharing) and Section (runtime selection)
- **Real-time Progress**: Visual feedback with parallel task progress display
- **Thread-Safe**: Built on Monitor-based synchronization for reliable concurrent execution

## 🚀 Quick Start

```ruby
require 'taski'

# Define tasks with dependencies
class DatabaseSetup < Taski::Task
  exports :connection_string

  def run
    @connection_string = "postgresql://localhost/myapp"
    puts "Database configured"
  end
end

class CacheSetup < Taski::Task
  exports :cache_url

  def run
    @cache_url = "redis://localhost:6379"
    puts "Cache configured"
  end
end

class APIServer < Taski::Task
  def run
    # Dependencies execute automatically and in parallel
    puts "Starting API with #{DatabaseSetup.connection_string}"
    puts "Using cache at #{CacheSetup.cache_url}"
  end
end

# Run any task - dependencies resolve and execute in parallel
APIServer.run
# => Database configured
# => Cache configured
# => Starting API with postgresql://localhost/myapp
# => Using cache at redis://localhost:6379
```

## Core Concepts

Taski provides two complementary APIs:

### 1. Exports API - Value Sharing Between Tasks
```ruby
class Config < Taski::Task
  exports :app_name, :port

  def run
    @app_name = "MyApp"
    @port = 3000
  end
end

class Server < Taski::Task
  def run
    # Automatically depends on Config task
    puts "Starting #{Config.app_name} on port #{Config.port}"
  end
end
```

### 2. Section API - Runtime Implementation Selection
```ruby
class DatabaseSection < Taski::Section
  interfaces :host, :port

  def impl
    # Select implementation at runtime
    ENV['RAILS_ENV'] == 'production' ? ProductionDB : LocalDB
  end
end

class ProductionDB < Taski::Task
  exports :host, :port
  def run
    @host = "prod.example.com"
    @port = 5432
  end
end
```

**When to use each:**
- **Exports**: Share computed values or side effects between tasks
- **Section**: Switch implementations based on environment or conditions

## Key Features

- **Parallel Execution**: Independent tasks run concurrently using threads
- **Static Analysis**: Dependencies detected automatically via Prism AST parsing
- **Thread-Safe**: Monitor-based synchronization ensures safe concurrent access
- **Progress Display**: Real-time visual feedback with spinner animations and timing
- **Tree Visualization**: See your dependency graph structure
- **Graceful Abort**: Stop execution cleanly without starting new tasks (Ctrl+C)

### Parallel Progress Display

Enable real-time progress visualization:

```bash
TASKI_FORCE_PROGRESS=1 ruby your_script.rb
```

Output example:
```
⠋ DatabaseSetup (running)
⠙ CacheSetup (running)
✅ DatabaseSetup (123.4ms)
✅ CacheSetup (98.2ms)
⠸ WebServer (running)
✅ WebServer (45.1ms)
```

### Tree Visualization

```ruby
puts WebServer.tree
# => WebServer
# => └── Config
# =>     ├── Database
# =>     └── Cache
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
rake test      # Run all tests
rake standard  # Check code style
```

## 📚 Learn More

- **[Examples](examples/)**: Practical examples from basic to advanced patterns
- **[Tests](test/)**: Comprehensive test suite showing real-world usage
- **[Source Code](lib/taski/)**: Clean, well-documented implementation
  - `lib/taski/task.rb` - Core Task implementation with exports API
  - `lib/taski/section.rb` - Section API for runtime selection
  - `lib/taski/execution/` - Parallel execution engine
  - `lib/taski/static_analysis/` - Prism-based dependency analyzer

## Support

Bug reports and pull requests welcome at https://github.com/ahogappa/taski.

## License

MIT License

---

**Taski** - Parallel task execution with automatic dependency resolution. 🚀
