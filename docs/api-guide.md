# API Guide

This guide provides detailed documentation for Taski's three APIs: Exports, Define, and Section.

## Overview

Taski provides three complementary APIs for different dependency scenarios:

- **Exports API**: Static dependencies with side effects
- **Define API**: Dynamic dependencies without side effects  
- **Section API**: Runtime implementation selection

## Exports API - Static Dependencies

The Exports API is ideal for static values and operations with side effects.

### Basic Usage

```ruby
class ConfigLoader < Taski::Task
  exports :app_name, :version, :database_url
  
  def run
    @app_name = "MyApp"
    @version = "1.0.0"
    @database_url = "postgresql://localhost/myapp"
    puts "Configuration loaded"
  end
end

class Server < Taski::Task
  def run
    puts "Starting #{ConfigLoader.app_name} v#{ConfigLoader.version}"
    puts "Database: #{ConfigLoader.database_url}"
  end
end

Server.run
# => Configuration loaded
# => Starting MyApp v1.0.0
# => Database: postgresql://localhost/myapp
```

### Multiple Dependencies

```ruby
class Database < Taski::Task
  exports :connection
  
  def run
    @connection = "db-connection-#{Time.now.to_i}"
    puts "Database connected"
  end
end

class Cache < Taski::Task
  exports :redis_client
  
  def run
    @redis_client = "redis-client-#{Time.now.to_i}"
    puts "Cache connected"
  end
end

class Application < Taski::Task
  def run
    puts "App starting with DB: #{Database.connection}"
    puts "App starting with Cache: #{Cache.redis_client}"
  end
end

Application.run
# => Database connected
# => Cache connected
# => App starting with DB: db-connection-1234567890
# => App starting with Cache: redis-client-1234567890
```

### When to Use Exports API

- **Static configuration values**: File paths, settings, constants
- **Side effects**: Database connections, file I/O, network calls
- **Predictable dependencies**: When the dependency chain is known at class definition time

## Define API - Dynamic Dependencies

The Define API enables runtime-dependent values without side effects.

### Basic Usage

```ruby
class EnvironmentConfig < Taski::Task
  define :database_host, -> {
    case ENV['RAILS_ENV']
    when 'production'
      'prod-db.example.com'
    when 'staging'
      'staging-db.example.com'
    else
      'localhost'
    end
  }
  
  define :redis_url, -> {
    case ENV['RAILS_ENV']
    when 'production'
      'redis://prod-redis.example.com:6379'
    else
      'redis://localhost:6379'
    end
  }
  
  def run
    puts "Database: #{database_host}"
    puts "Redis: #{redis_url}"
  end
end

ENV['RAILS_ENV'] = 'development'
EnvironmentConfig.run
# => Database: localhost
# => Redis: redis://localhost:6379

ENV['RAILS_ENV'] = 'production'
EnvironmentConfig.reset!
EnvironmentConfig.run
# => Database: prod-db.example.com
# => Redis: redis://prod-redis.example.com:6379
```

### Dynamic Dependencies Between Tasks

```ruby
class FeatureFlags < Taski::Task
  define :use_new_algorithm, -> {
    ENV['USE_NEW_ALGORITHM'] == 'true'
  }
end

class DataProcessor < Taski::Task
  define :algorithm, -> {
    FeatureFlags.use_new_algorithm ? 'v2' : 'v1'
  }
  
  def run
    puts "Using algorithm: #{algorithm}"
  end
end

ENV['USE_NEW_ALGORITHM'] = 'false'
DataProcessor.run
# => Using algorithm: v1

ENV['USE_NEW_ALGORITHM'] = 'true'
DataProcessor.reset!
DataProcessor.run
# => Using algorithm: v2
```

### Forward References with ref()

Use `ref()` when you need to reference a class that's defined later:

```ruby
class EarlyTask < Taski::Task
  define :config, -> {
    ref("LaterTask").settings
  }
  
  def run
    puts "Early task using: #{config}"
  end
end

class LaterTask < Taski::Task
  exports :settings
  
  def run
    @settings = "late-configuration"
  end
end

EarlyTask.run
# => Early task using: late-configuration
```

**Important**: Use `ref()` sparingly. Prefer direct class references when possible:

```ruby
# ✅ Preferred
define :config, -> { LaterTask.settings }

# ⚠️ Only when forward declaration needed
define :config, -> { ref("LaterTask").settings }
```

### When to Use Define API

- **Environment-specific logic**: Different behavior per environment
- **Feature flags**: Conditional functionality
- **Runtime configuration**: Values that change based on current state
- **No side effects**: Pure computation only

## Section API - Abstraction Layers

The Section API provides runtime implementation selection with static analysis support.

### Basic Usage

```ruby
class DatabaseSection < Taski::Section
  interface :host, :port, :connection_string
  
  def impl
    case ENV['RAILS_ENV']
    when 'production'
      ProductionDB
    when 'test'
      TestDB
    else
      DevelopmentDB
    end
  end
  
  class ProductionDB < Taski::Task
    def run
      @host = "prod-db.example.com"
      @port = 5432
      @connection_string = "postgresql://#{@host}:#{@port}/myapp_production"
    end
  end
  
  class TestDB < Taski::Task
    def run
      @host = ":memory:"
      @port = nil
      @connection_string = "sqlite3::memory:"
    end
  end
  
  class DevelopmentDB < Taski::Task
    def run
      @host = "localhost"
      @port = 5432
      @connection_string = "postgresql://#{@host}:#{@port}/myapp_development"
    end
  end
end

class Application < Taski::Task
  def run
    puts "Connecting to: #{DatabaseSection.connection_string}"
    puts "Host: #{DatabaseSection.host}, Port: #{DatabaseSection.port}"
  end
end

ENV['RAILS_ENV'] = 'development'
Application.run
# => Connecting to: postgresql://localhost:5432/myapp_development
# => Host: localhost, Port: 5432

ENV['RAILS_ENV'] = 'production'
DatabaseSection.reset!
Application.run
# => Connecting to: postgresql://prod-db.example.com:5432/myapp_production
# => Host: prod-db.example.com, Port: 5432
```

### Complex Section Hierarchies

```ruby
class LoggingSection < Taski::Section
  interface :logger, :level
  
  def impl
    ENV['LOG_FORMAT'] == 'json' ? JsonLogging : SimpleLogging
  end
  
  class JsonLogging < Taski::Task
    def run
      @logger = "JsonLogger"
      @level = "INFO"
    end
  end
  
  class SimpleLogging < Taski::Task
    def run
      @logger = "SimpleLogger"
      @level = "DEBUG"
    end
  end
end

class ServiceSection < Taski::Section
  interface :api_endpoint, :timeout
  
  def impl
    ENV['SERVICE_MODE'] == 'mock' ? MockService : RealService
  end
  
  class MockService < Taski::Task
    def run
      @api_endpoint = "http://localhost:3000/mock"
      @timeout = 1
    end
  end
  
  class RealService < Taski::Task
    def run
      @api_endpoint = LoggingSection.level == 'DEBUG' ? 
        "https://api-debug.example.com" : 
        "https://api.example.com"
      @timeout = 30
    end
  end
end

class MainApp < Taski::Task
  def run
    puts "Logger: #{LoggingSection.logger} (#{LoggingSection.level})"
    puts "API: #{ServiceSection.api_endpoint} (timeout: #{ServiceSection.timeout}s)"
  end
end

ENV['LOG_FORMAT'] = 'simple'
ENV['SERVICE_MODE'] = 'real'
MainApp.run
# => Logger: SimpleLogger (DEBUG)
# => API: https://api-debug.example.com (timeout: 30s)
```

### When to Use Section API

- **Implementation abstraction**: Different adapters or strategies
- **Environment-specific implementations**: Dev/test/prod variations
- **Conditional implementations**: Based on runtime state
- **Clean interfaces**: When you want to hide implementation details

## API Comparison

| Feature | Exports API | Define API | Section API |
|---------|-------------|------------|-------------|
| **Side Effects** | ✅ Allowed | ❌ Not allowed | ✅ Allowed |
| **Static Analysis** | ✅ Full support | ✅ Full support | ✅ Full support |
| **Runtime Selection** | ❌ No | ✅ Limited | ✅ Full support |
| **Interface Definition** | ❌ No | ❌ No | ✅ Yes |
| **Caching** | ✅ Yes | ✅ Yes | ✅ Yes |
| **Reset Support** | ✅ Yes | ✅ Yes | ✅ Yes |

## Best Practices

### 1. Choose the Right API

```ruby
# ✅ Good: Static configuration with Exports
class Config < Taski::Task
  exports :app_name, :version
  def run
    @app_name = "MyApp"
    @version = "1.0.0"
  end
end

# ✅ Good: Environment logic with Define
class EnvConfig < Taski::Task
  define :debug_mode, -> { ENV['DEBUG'] == 'true' }
end

# ✅ Good: Implementation selection with Section
class DatabaseSection < Taski::Section
  interface :connection
  def impl
    production? ? PostgreSQL : SQLite
  end
end
```

### 2. Minimize ref() Usage

```ruby
# ✅ Preferred: Direct reference
class TaskB < Taski::Task
  exports :value
  def run; @value = "hello"; end
end

class TaskA < Taski::Task
  define :result, -> { TaskB.value.upcase }
end

# ⚠️ Only when necessary: Forward reference
class TaskA < Taski::Task
  define :result, -> { ref("TaskB").value.upcase }
end

class TaskB < Taski::Task
  exports :value
  def run; @value = "hello"; end
end
```

### 3. Keep Define Blocks Pure

```ruby
# ✅ Good: Pure computation
define :config_path, -> {
  ENV['CONFIG_PATH'] || '/etc/myapp/config.yml'
}

# ❌ Bad: Side effects
define :config, -> {
  File.read('/etc/config.yml')  # File I/O is a side effect
}
```

### 4. Use Clear Interface Definitions

```ruby
# ✅ Good: Clear interface
class DatabaseSection < Taski::Section
  interface :host, :port, :username, :password, :database
  
  # Implementation classes follow interface
end

# ❌ Bad: Unclear interface
class DatabaseSection < Taski::Section
  # No interface definition - unclear what's available
end
```

## Advanced Patterns

### Conditional Dependencies

```ruby
class OptionalService < Taski::Task
  define :enabled, -> { ENV['OPTIONAL_SERVICE'] == 'true' }
  
  def run
    if enabled
      puts "Optional service is enabled"
    else
      puts "Optional service is disabled"
    end
  end
end
```

### Dependency Injection

```ruby
class ServiceSection < Taski::Section
  interface :client
  
  def impl
    case ENV['SERVICE_PROVIDER']
    when 'aws' then AWSService
    when 'gcp' then GCPService
    else LocalService
    end
  end
  
  class AWSService < Taski::Task
    def run; @client = "AWS Client"; end
  end
  
  class GCPService < Taski::Task
    def run; @client = "GCP Client"; end
  end
  
  class LocalService < Taski::Task
    def run; @client = "Local Client"; end
  end
end
```

### Mixed API Usage

```ruby
class Config < Taski::Task
  exports :base_url
  def run; @base_url = "https://api.example.com"; end
end

class ApiSection < Taski::Section
  interface :endpoint
  
  def impl
    ENV['API_VERSION'] == 'v2' ? ApiV2 : ApiV1
  end
  
  class ApiV1 < Taski::Task
    def run
      @endpoint = "#{Config.base_url}/v1"
    end
  end
  
  class ApiV2 < Taski::Task
    define :version_suffix, -> { ENV['BETA'] == 'true' ? '-beta' : '' }
    
    def run
      @endpoint = "#{Config.base_url}/v2#{version_suffix}"
    end
  end
end
```

This combination shows how all three APIs can work together in a single application.