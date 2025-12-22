# Taski

[![CI](https://github.com/ahogappa/taski/workflows/CI/badge.svg)](https://github.com/ahogappa/taski/actions/workflows/ci.yml)
[![Codecov](https://codecov.io/gh/ahogappa/taski/branch/master/graph/badge.svg)](https://codecov.io/gh/ahogappa/taski)
[![Gem Version](https://badge.fury.io/rb/taski.svg)](https://badge.fury.io/rb/taski)

**Taski** is a Ruby framework for building task dependency graphs with automatic resolution and parallel execution.

> **Name Origin**: "Taski" comes from the Japanese word "襷" (tasuki), a sash used in relay races. Just like how runners pass the sash to the next teammate, tasks in Taski pass dependencies to one another in a continuous chain.

## Features

- **Automatic Dependency Resolution**: Dependencies detected via static analysis
- **Parallel Execution**: Independent tasks run concurrently for maximum performance
- **Two Simple APIs**: Exports (value sharing) and Section (runtime selection)
- **Real-time Progress**: Visual feedback with parallel task progress display
- **Thread-Safe**: Built on Monitor-based synchronization for reliable concurrent execution

## Quick Start

```ruby
require 'taski'

class DatabaseSetup < Taski::Task
  exports :connection_string

  def run
    @connection_string = "postgresql://localhost/myapp"
  end
end

class CacheSetup < Taski::Task
  exports :cache_url

  def run
    @cache_url = "redis://localhost:6379"
  end
end

class APIServer < Taski::Task
  def run
    # Dependencies execute automatically and in parallel
    puts "DB: #{DatabaseSetup.connection_string}"
    puts "Cache: #{CacheSetup.cache_url}"
  end
end

APIServer.run
```

## Installation

```ruby
gem 'taski'
```

## Core Concepts

### Exports - Value Sharing Between Tasks

Share computed values between tasks:

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
    puts "Starting #{Config.app_name} on port #{Config.port}"
  end
end
```

### Section - Runtime Implementation Selection

Switch implementations based on environment:

```ruby
class DatabaseSection < Taski::Section
  interfaces :host, :port

  class Production < Taski::Task
    def run
      @host = "prod.example.com"
      @port = 5432
    end
  end

  class Development < Taski::Task
    def run
      @host = "localhost"
      @port = 5432
    end
  end

  def impl
    ENV['RAILS_ENV'] == 'production' ? Production : Development
  end
end

class App < Taski::Task
  def run
    puts "Connecting to #{DatabaseSection.host}:#{DatabaseSection.port}"
  end
end
```

> **Note**: Nested implementation classes automatically inherit Section's `interfaces` as `exports`.

## Advanced Usage

### Args - Runtime Information and Options

Pass custom options and access execution context from any task:

```ruby
class DeployTask < Taski::Task
  def run
    # User-defined options
    env = Taski.args[:env]
    debug = Taski.args.fetch(:debug, false)

    # Runtime information
    puts "Working directory: #{Taski.args.working_directory}"
    puts "Started at: #{Taski.args.started_at}"
    puts "Root task: #{Taski.args.root_task}"
    puts "Deploying to: #{env}"
  end
end

# Pass options when running
DeployTask.run(args: { env: "production", debug: true })
```

Args API:
- `Taski.args[:key]` - Get option value (nil if not set)
- `Taski.args.fetch(:key, default)` - Get with default value
- `Taski.args.key?(:key)` - Check if option exists
- `Taski.args.working_directory` - Execution directory
- `Taski.args.started_at` - Execution start time
- `Taski.args.root_task` - First task class called

### Execution Model

```ruby
# Each class method call creates fresh execution
RandomTask.value  # => 42
RandomTask.value  # => 99 (different value - fresh execution)

# Instance-level caching
instance = RandomTask.new
instance.run        # => 42
instance.run        # => 42 (cached within instance)
instance.value      # => 42

# Dependencies within same execution share results
DoubleConsumer.run  # RandomTask runs once, both accesses get same value
```

### Aborting Execution

Stop all pending tasks when a critical error occurs:

```ruby
class CriticalTask < Taski::Task
  def run
    if fatal_error?
      raise Taski::TaskAbortException, "Cannot continue"
    end
  end
end
```

When `TaskAbortException` is raised, no new tasks will start. Already running tasks will complete, then execution stops.

### Progress Display

Tree-based progress visualization is enabled by default:

```
WebServer (Task)
├── ⠋ Config (Task) ...
│   ├── ✅ Database (Task) 45.2ms
│   └── ⠙ Cache (Task) ...
└── ◻ Server (Task)
```

To disable: `TASKI_PROGRESS_DISABLE=1 ruby your_script.rb`

### Tree Visualization

```ruby
puts WebServer.tree
# WebServer (Task)
# └── Config (Task)
#     ├── Database (Task)
#     └── Cache (Task)
```

## Development

```bash
rake test      # Run all tests
rake standard  # Check code style
```

## Support

Bug reports and pull requests welcome at https://github.com/ahogappa/taski.

## License

MIT License
