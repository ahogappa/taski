# Conditional Execution Design for Taski Framework

## Overview

This document explores the design and implementation of conditional execution features for the Taski framework. The goal is to allow tasks to execute only when certain conditions are met, while maintaining the framework's core principles of declarative design, static analyzability, and simplicity.

## Background

Currently, Taski executes all tasks unconditionally once their dependencies are resolved. However, real-world scenarios often require:
- Environment-specific task execution
- Feature flag-based conditional processing  
- Cache-based execution optimization
- Resource-aware task skipping

## Core Problem: Build vs Clean Execution Asymmetry

### The Challenge

A critical issue identified during design is the potential mismatch between build-time and clean-time execution conditions:

```ruby
class TemporaryFileTask < Taski::Task
  exports :temp_file
  
  # Only execute in development environment
  run_if -> { ENV['RAILS_ENV'] == 'development' }
  
  def build
    @temp_file = '/tmp/debug_output.log'
    File.write(@temp_file, debug_data)
  end
  
  def clean
    File.delete(@temp_file) if File.exist?(@temp_file)
  end
end
```

**Problem Scenario:**
1. **Build time**: `ENV['RAILS_ENV'] = 'development'` → Task executes, file created
2. **Production deployment**: Environment variables change
3. **Clean time**: `ENV['RAILS_ENV'] = 'production'` → Task skipped, **file remains**

### Why Record-Based Approaches Fail

Initial consideration was given to recording execution state during build and using it during clean:

```ruby
def clean
  return unless was_executed_during_build?
  cleanup_work
end
```

**Critical flaw**: Clean operations can be called independently of build operations. Clean is not always preceded by build, making execution history unreliable.

## Proposed API Designs

### 1. Basic Conditional Execution

```ruby
class ConditionalTask < Taski::Task
  exports :result
  
  # Execute only if condition is true
  run_if -> { ENV['RAILS_ENV'] == 'production' }
  
  # Skip if condition is true
  skip_if -> { File.exist?('cache/result.json') }
  
  def build
    @result = expensive_operation
  end
end
```

### 2. Environment-Based Conditions

```ruby
class EnvironmentTask < Taski::Task
  exports :config
  
  # Concise environment-based syntax
  when_env 'production', 'staging'
  unless_env 'test'
  
  def build
    @config = load_production_config
  end
end
```

### 3. Feature Flag Support

```ruby
class FeatureTask < Taski::Task
  exports :feature_result
  
  when_feature 'new_feature_enabled'
  unless_feature 'legacy_mode'
  
  def build
    @feature_result = new_feature_implementation
  end
end
```

### 4. Guard Clause Style

```ruby
class GuardedTask < Taski::Task
  exports :result
  
  guard :check_prerequisites
  guard -> { system_resources_sufficient? }
  
  def build
    @result = resource_intensive_operation
  end
  
  private
  
  def check_prerequisites
    File.exist?('/required/file') && database_accessible?
  end
end
```

### 5. Conditional Dependencies

```ruby
class AdaptiveDependency < Taski::Task
  exports :output
  
  # Dynamic dependency definition
  dependencies do
    deps = [BaseTask]
    deps << CacheTask if ENV['USE_CACHE'] == 'true'
    deps << ProcessingTask unless cached_result_exists?
    deps
  end
  
  def build
    # adaptive logic
  end
end
```

### 6. Conditional Block Execution

```ruby
class MultiConditionalTask < Taski::Task
  exports :results
  
  def build
    @results = {}
    
    when_condition(-> { feature_enabled?('feature_a') }) do
      @results[:feature_a] = build_feature_a
    end
    
    when_condition(-> { ENV['DEBUG'] == 'true' }) do
      @results[:debug_info] = collect_debug_info
    end
  end
end
```

### 7. Cache-Based Conditions

```ruby
class CachedTask < Taski::Task
  exports :processed_data
  
  # Skip if result exists in cache
  skip_if_cached 'processed_data.json'
  
  # Timestamp-based cache invalidation
  skip_if_fresh_cache 'processed_data.json', max_age: 1.hour
  
  def build
    @processed_data = expensive_data_processing
  end
end
```

## Solution Approaches for Build/Clean Asymmetry

### Approach 1: State Inspection Based (Recommended)

Instead of relying on execution history, inspect actual system state:

```ruby
class IntelligentConditionalTask < Taski::Task
  exports :result
  
  # Build condition
  build_when -> { feature_enabled? }
  
  def build
    @result = create_feature_output
  end
  
  def clean
    # Inspect actual state to determine cleanup needs
    return unless cleanup_needed?
    perform_cleanup
  end
  
  private
  
  def cleanup_needed?
    # Check actual state: files, processes, caches, etc.
    File.exist?('/tmp/feature_output') ||
    process_running?('feature_process') ||
    cache_exists?('feature_cache')
  end
end
```

### Approach 2: Symmetric Conditions

Use the same condition for both build and clean:

```ruby
class SymmetricTask < Taski::Task
  exports :resource
  
  # Same condition for build and clean
  when_condition -> { development_mode? && feature_enabled? }
  
  def build
    @resource = create_resource if should_execute?
  end
  
  def clean
    cleanup_resource if should_execute?
  end
end
```

### Approach 3: Explicit Separation

Allow independent conditions for build and clean:

```ruby
class AsymmetricTask < Taski::Task
  exports :feature_data
  
  build_if -> { feature_flag_enabled? }
  clean_if -> { feature_exists? || force_cleanup? }
  
  def build
    @feature_data = build_feature
  end
  
  def clean
    cleanup_feature_artifacts
  end
  
  private
  
  def feature_exists?
    # Check if feature artifacts actually exist
    feature_files_exist? || feature_processes_running?
  end
end
```

### Approach 4: Safety-First Design

Build is conditional, clean is always unconditional:

```ruby
class SafeConditionalTask < Taski::Task
  exports :result
  
  # Build only under certain conditions
  build_if -> { should_process? }
  
  def build
    @result = expensive_operation
  end
  
  def clean
    # Clean always executes (safety first)
    cleanup_if_exists
  end
end
```

## Recommended Implementation

### Core API Structure

```ruby
module Taski
  class Task
    class << self
      def build_if(condition)
        @build_condition = condition
      end
      
      # Clean is unconditional by default, can be overridden
      def clean_if(condition)
        @clean_condition = condition
      end
      
      # Convenience: same condition for both build and clean
      def when_condition(condition)
        @build_condition = condition
        @clean_condition = condition
      end
      
      # Safety-first: conditional build, unconditional clean
      def safe_build_if(condition)
        @build_condition = condition
        @clean_condition = -> { true }
      end
    end
    
    def should_execute_build?
      condition = self.class.instance_variable_get(:@build_condition)
      return true unless condition
      evaluate_condition(condition)
    end
    
    def should_execute_clean?
      condition = self.class.instance_variable_get(:@clean_condition)
      return true unless condition
      evaluate_condition(condition)
    end
    
    private
    
    def evaluate_condition(condition)
      case condition
      when Proc
        instance_eval(&condition)
      when Symbol
        send(condition)
      else
        !!condition
      end
    end
  end
end
```

### Usage Patterns

#### Pattern 1: State Inspection Based (Recommended)

```ruby
class FileProcessingTask < Taski::Task
  exports :processed_file
  
  build_if -> { input_file_exists? && processing_enabled? }
  
  def build
    @processed_file = process_input_file
  end
  
  def clean
    # Check actual state for cleanup decisions
    cleanup_output_files if output_files_exist?
    cleanup_temp_dirs if temp_dirs_exist?
    stop_background_process if process_running?
  end
  
  private
  
  def output_files_exist?
    Dir.glob('/tmp/processing_*').any?
  end
end
```

#### Pattern 2: Symmetric Conditions

```ruby
class EnvironmentSpecificTask < Taski::Task
  exports :env_config
  
  # Same condition for both build and clean
  when_condition -> { ENV['RAILS_ENV'] == 'development' }
  
  def build
    @env_config = create_dev_config
  end
  
  def clean
    remove_dev_config
  end
end
```

#### Pattern 3: Explicit Separation

```ruby
class AsymmetricTask < Taski::Task
  exports :feature_data
  
  build_if -> { feature_flag_enabled? }
  clean_if -> { feature_exists? || force_cleanup? }
  
  def build
    @feature_data = build_feature
  end
  
  def clean
    cleanup_feature_artifacts
  end
end
```

## Implementation Priorities

1. **Core conditional API** (`build_if`, `clean_if`, `when_condition`)
2. **Environment helpers** (`when_env`, `unless_env`)
3. **Cache helpers** (`skip_if_cached`, `skip_if_fresh_cache`)
4. **Logging integration** (condition evaluation results)
5. **Comprehensive testing**

## Benefits

- **Environment-specific execution** - Different behavior in development/production
- **Cache optimization** - Skip execution when results exist
- **Feature flags** - Gradual feature rollout
- **Resource protection** - Safe handling of resource constraints
- **Dependency optimization** - Dynamic dependency resolution based on conditions

## Safety Considerations

1. **Default behavior**: Clean operations should be unconditional by default
2. **State inspection**: Prefer actual state checking over execution history
3. **Explicit control**: Allow independent build/clean conditions when needed
4. **Logging**: Record condition evaluation for debugging
5. **Fallback safety**: Always provide safe fallback behavior

## Next Steps

1. Implement basic conditional API
2. Add comprehensive test coverage
3. Integrate with existing logging system
4. Document usage patterns and best practices
5. Consider integration with static analysis capabilities

---

*This document represents the current thinking on conditional execution design. It should be updated as implementation progresses and new insights are gained.*