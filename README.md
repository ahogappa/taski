# Taski

[![CI](https://github.com/ahogappa/taski/workflows/CI/badge.svg)](https://github.com/ahogappa/taski/actions/workflows/ci.yml)
[![Codecov](https://codecov.io/gh/ahogappa/taski/branch/master/graph/badge.svg)](https://codecov.io/gh/ahogappa/taski)
[![Gem Version](https://badge.fury.io/rb/taski.svg)](https://badge.fury.io/rb/taski)

> **🚧 Development Status:** Taski is currently under active development. Not yet recommended for production use.

**Taski** is a Ruby framework for building task dependency graphs with automatic resolution and execution.

> **Name Origin**: "Taski" comes from the Japanese word "襷" (tasuki), a sash used in relay races. Just like how runners pass the sash to the next teammate, tasks in Taski pass dependencies to one another in a continuous chain.

## Why Taski?

Build complex workflows by defining tasks and their dependencies - Taski automatically resolves execution order and manages the entire process.

- **Automatic Resolution**: No manual orchestration needed
- **Three APIs**: Static (Exports), Dynamic (Define), Abstraction (Section)
- **Built-in Features**: Progress display, error handling, logging
- **Error Handling**: Comprehensive exception management and recovery

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

class APIServer < Taski::Task
  def run
    puts "Starting API with #{DatabaseSetup.connection_string}"
  end
end

# Run any task - dependencies execute automatically
APIServer.run
# => Database configured
# => Starting API with postgresql://localhost/myapp
```

## Core Concepts

Taski provides three APIs for different dependency scenarios:

### 1. Exports API (Static Dependencies)
```ruby
class Config < Taski::Task
  exports :app_name
  def run; @app_name = "MyApp"; end
end

class Server < Taski::Task
  def run; puts "Starting #{Config.app_name}"; end
end
```

### 2. Define API (Dynamic Dependencies)
```ruby
class EnvConfig < Taski::Task
  define :db_host, -> { ENV['DB_HOST'] || 'localhost' }
end
```

### 3. Section API (Abstraction Layers)
```ruby
class DatabaseSection < Taski::Section
  interface :host
  def impl; production? ? ProductionDB : LocalDB; end
end
```

**When to use each:**
- **Exports**: Static values and side effects
- **Define**: Environment-based logic
- **Section**: Runtime implementation selection

## Key Features

- **Automatic Dependency Resolution**: No manual orchestration needed
- **Error Handling**: Comprehensive exception management and recovery
- **Visual Progress**: Real-time feedback with spinners and timing
- **Error Handling**: Circular dependency detection and recovery
- **Signal Support**: Graceful interruption (Ctrl+C)
- **Flexible Logging**: Multiple output formats
- **Tree Visualization**: See your dependency graph

```ruby
# Visualize dependencies
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

- **[API Guide](docs/api-guide.md)**: Detailed documentation for all three APIs
- **[Advanced Features](docs/advanced-features.md)**: Progress display, signal handling, logging
- **[Error Handling](docs/error-handling.md)**: Recovery strategies and debugging
- **[Examples](examples/)**: Practical examples from basic to advanced patterns
- **[Tests](test/)**: Comprehensive test suite showing usage patterns
- **[Source Code](lib/taski/)**: Well-documented implementation

## Support

Bug reports and pull requests welcome at https://github.com/ahogappa/taski.

## License

MIT License

---

**Taski** - Build dependency graphs with elegant Ruby code. 🚀
