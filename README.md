# Taski

> **🚧 Development Status:** Taski is currently under active development and the API may change. Not yet recommended for production use.

**Taski** is a powerful Ruby framework for building task dependency graphs with automatic resolution and execution. It provides two complementary APIs for different use cases: static dependencies through exports and dynamic dependencies through define.

## 🎯 Key Features

- **Automatic Dependency Resolution**: Dependencies are detected automatically through static analysis and runtime evaluation
- **Two Complementary APIs**: Choose the right approach for your use case
  - **Exports API**: For simple, static dependencies
  - **Define API**: For complex, dynamic dependencies based on runtime conditions
- **Thread-Safe Execution**: Safe for concurrent access with Monitor-based synchronization
- **Circular Dependency Detection**: Prevents infinite loops with clear error messages
- **Memory Leak Prevention**: Built-in reset mechanisms for long-running applications
- **Topological Execution**: Tasks execute in correct dependency order automatically
- **Reverse Cleanup**: Clean operations run in reverse dependency order

## 🚀 Quick Start

```ruby
require 'taski'

# Simple static dependency using Exports API
class DatabaseSetup < Taski::Task
  exports :connection_string

  def build
    @connection_string = "postgresql://localhost/myapp"
    puts "Database configured"
  end
end

class APIServer < Taski::Task
  exports :port

  def build
    # Automatic dependency: DatabaseSetup will be built first
    puts "Starting API with #{DatabaseSetup.connection_string}"
    @port = 3000
  end
end

# Execute - dependencies are resolved automatically
APIServer.build
# => Database configured
# => Starting API with postgresql://localhost/myapp
```

## 📚 API Guide

### Exports API - Static Dependencies

Use the **Exports API** when you have simple, predictable dependencies:

```ruby
class ConfigLoader < Taski::Task
  exports :app_name, :version

  def build
    @app_name = "MyApp"
    @version = "1.0.0"
  end
end

class Deployment < Taski::Task
  exports :deploy_url

  def build
    # Static dependency - always uses ConfigLoader
    @deploy_url = "https://#{ConfigLoader.app_name}.example.com"
  end
end
```

### Define API - Dynamic Dependencies

Use the **Define API** when dependencies change based on runtime conditions:

```ruby
class EnvironmentConfig < Taski::Task
  define :database_service, -> {
    # Dynamic dependency based on environment
    case ENV['RAILS_ENV']
    when 'production'
      ProductionDatabase.setup
    when 'staging'
      StagingDatabase.setup
    else
      DevelopmentDatabase.setup
    end
  }

  define :cache_strategy, -> {
    # Dynamic dependency based on feature flags
    if FeatureFlag.enabled?(:redis_cache)
      RedisCache.configure
    else
      MemoryCache.configure
    end
  }

  def build
    puts "Using #{database_service}"
    puts "Cache: #{cache_strategy}"
  end
end
```

> **⚠️ Note:** The `define` API uses dynamic method definition, which may generate Ruby warnings about method redefinition. This is expected behavior due to the dependency resolution mechanism and does not affect functionality.

### When to Use Each API

| Use Case | Recommended API | Example |
|----------|----------------|---------|
| Simple value exports | Exports API | Configuration values, file paths |
| Environment-specific logic | Define API | Different services per environment |
| Feature flag dependencies | Define API | Optional components based on flags |
| Conditional processing | Define API | Different algorithms based on input |
| Static file dependencies | Exports API | Build artifacts, compiled assets |

## 🔧 Advanced Features

### Thread Safety

Taski is thread-safe and handles concurrent access gracefully:

```ruby
# Multiple threads can safely access the same task
threads = 5.times.map do
  Thread.new { MyTask.some_value }
end

# All threads get the same instance - built only once
results = threads.map(&:value)
```

### Error Handling

Comprehensive error handling with custom exception types:

```ruby
begin
  TaskWithCircularDep.build
rescue Taski::CircularDependencyError => e
  puts "Circular dependency detected: #{e.message}"
rescue Taski::TaskBuildError => e
  puts "Build failed: #{e.message}"
end
```

### Lifecycle Management

Full control over task lifecycle:

```ruby
class ProcessingTask < Taski::Task
  def build
    # Setup and processing logic
    puts "Processing data..."
  end

  def clean
    # Cleanup logic (runs in reverse dependency order)
    puts "Cleaning up temporary files..."
  end
end

# Build dependencies in correct order
ProcessingTask.build

# Clean in reverse order
ProcessingTask.clean
```

## 🏗️ Complex Example

Here's a realistic example showing both APIs working together:

```ruby
# Environment configuration using Define API
class Environment < Taski::Task
  define :database_url, -> {
    case ENV['RAILS_ENV']
    when 'production'
      ProductionDB.connection_string
    when 'test'
      TestDB.connection_string
    else
      "sqlite3://development.db"
    end
  }

  define :redis_config, -> {
    if FeatureFlag.enabled?(:redis_cache)
      RedisService.configuration
    else
      nil
    end
  }
end

# Static configuration using Exports API
class AppConfig < Taski::Task
  exports :app_name, :version, :port

  def build
    @app_name = "MyWebApp"
    @version = "2.1.0"
    @port = ENV.fetch('PORT', 3000).to_i
  end
end

# Application startup combining both APIs
class Application < Taski::Task
  def build
    puts "Starting #{AppConfig.app_name} v#{AppConfig.version}"
    puts "Database: #{Environment.database_url}"
    puts "Redis: #{Environment.redis_config || 'disabled'}"
    puts "Port: #{AppConfig.port}"

    # Start the application...
  end

  def clean
    puts "Shutting down #{AppConfig.app_name}..."
    # Cleanup logic...
  end
end

# Everything runs in the correct order automatically
Application.build
```

## 📦 Installation

> **⚠️ Warning:** Taski is currently in development. API changes may occur. Use at your own risk in production environments.

Add this line to your application's Gemfile:

```ruby
gem 'taski'
```

And then execute:

```bash
bundle install
```

Or install it yourself as:

```bash
gem install taski
```

For development and testing purposes, you can also install directly from the repository:

```ruby
# In your Gemfile
gem 'taski', git: 'https://github.com/[USERNAME]/taski.git'
```

## 🧪 Testing

Taski includes comprehensive test coverage. Run the test suite:

```bash
bundle exec rake test
```

> **ℹ️ Note:** Test output may include warnings about method redefinition from the `define` API. These warnings are expected and can be safely ignored.


## 🏛️ Architecture

Taski is built with a modular architecture:

- **Task Base**: Core framework and constants
- **Exports API**: Static dependency resolution
- **Define API**: Dynamic dependency resolution
- **Instance Management**: Thread-safe lifecycle management
- **Dependency Resolver**: Topological sorting and analysis
- **Static Analyzer**: AST-based dependency detection

## 🚧 Development Status

**Taski is currently in active development and should be considered experimental.** While the core functionality is working and well-tested, the API may undergo changes as we refine the framework based on feedback and real-world usage.

### Current Development Phase

- ✅ **Core Framework**: Dependency resolution, both APIs, thread safety
- ✅ **Testing**: Comprehensive test suite with 38+ tests
- ✅ **Type Safety**: RBS definitions and Steep integration
- 🚧 **API Stability**: Some breaking changes may occur
- 🚧 **Performance**: Optimizations for large dependency graphs
- 🚧 **Documentation**: Examples and best practices

### Known Limitations

- **API Changes**: Breaking changes may occur in minor version updates
- **Production Readiness**: Not yet recommended for production environments
- **Static Analysis**: Works best with straightforward Ruby code patterns
- **Metaprogramming**: Complex metaprogramming may require manual dependency specification
- **Performance**: Not yet optimized for very large dependency graphs (1000+ tasks)
- **Method Redefinition Warnings**: Using `define` API may generate Ruby warnings about method redefinition (this is expected behavior)

### Future Development

The future direction of Taski will be determined based on community feedback, real-world usage, and identified needs. Development priorities may include areas such as performance optimization, enhanced static analysis, and improved documentation, but specific roadmap items have not yet been finalized.

### Contributing to Development

We welcome contributions during this development phase! Areas where help is especially appreciated:

- **Real-world Testing**: Try Taski in your projects and report issues
- **Performance Testing**: Test with large dependency graphs
- **API Feedback**: Suggest improvements to the developer experience
- **Documentation**: Help improve examples and guides

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/ahogappa/taski.

## License

The gem is available as open source under the [MIT License](LICENSE).

---

**Taski** - Build complex dependency graphs with simple, elegant Ruby code. 🚀

> **Experimental Software**: Please use responsibly and provide feedback to help us reach v1.0!
