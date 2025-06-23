# Parametrized Build Design

## Overview

Add support for `TaskClass.build(args)` to allow passing arguments to task execution while maintaining the core design principles of static dependency resolution.

## Design Goals

1. **Simple API**: `ProcessingTask.build(mode: :fast, input: data)`
2. **Backward Compatibility**: `ProcessingTask.build` (no args) works as before
3. **Static Dependencies**: `@dependencies` remains unchanged regardless of arguments
4. **Temporary Instances**: Parametrized builds don't affect singleton instance

## Implementation

### Core Changes to Task Base Class

```ruby
module Taski
  class Task
    class << self
      def build(**args)
        if args.empty?
          # Traditional build: singleton instance with caching
          ensure_instance_built
          self
        else
          # Parametrized build: temporary instance without caching
          build_with_args(args)
        end
      end
      
      private
      
      def build_with_args(args)
        # Resolve dependencies first (same as normal build)
        resolve_dependencies
        
        # Create temporary instance
        temp_instance = new
        temp_instance.instance_variable_set(:@build_args, args)
        
        # Build with logging
        build_start_time = Time.now
        begin
          Taski.logger.task_build_start(name.to_s, 
            dependencies: @dependencies || [],
            args: args)
          
          temp_instance.build
          
          duration = Time.now - build_start_time
          Taski.logger.task_build_complete(name.to_s, duration: duration)
          
          temp_instance
        rescue => e
          duration = Time.now - build_start_time
          Taski.logger.task_build_failed(name.to_s, error: e, duration: duration)
          raise TaskBuildError, "Failed to build task #{name} with args #{args}: #{e.message}"
        end
      end
    end
    
    # Instance method to access build arguments
    def build_args
      @build_args || {}
    end
  end
end
```

### Usage Patterns

#### Basic Parametrized Task
```ruby
class ProcessingTask < Taski::Task
  exports :result
  
  def build
    args = build_args
    mode = args[:mode] || :default
    input = args[:input] || load_default_input
    
    @result = case mode
              when :fast then fast_process(input)
              when :thorough then thorough_process(input, args)
              else default_process(input)
              end
  end
end

# Usage
default_instance = ProcessingTask.build                # => singleton instance
default_instance.result                                # => default result

fast_instance = ProcessingTask.build(mode: :fast)      # => temporary instance  
fast_instance.result                                    # => fast result
```

#### Task with Dependencies
```ruby
class DataProcessor < Taski::Task
  dependencies DataLoader  # Static dependency (unchanged)
  exports :processed_data
  
  def build
    args = build_args
    raw_data = DataLoader.data
    
    @processed_data = transform_data(
      raw_data,
      format: args[:format] || :json,
      compress: args[:compress] || false
    )
  end
end

# Dependencies are resolved normally
processor = DataProcessor.build(format: :xml, compress: true)
puts processor.processed_data
```

#### Conditional Processing
```ruby
class ConditionalTask < Taski::Task
  exports :output
  
  def build
    args = build_args
    
    @output = if args[:skip_expensive]
                quick_calculation
              else
                expensive_calculation(args[:precision] || :standard)
              end
  end
end

# Different execution paths based on arguments
quick = ConditionalTask.build(skip_expensive: true)
detailed = ConditionalTask.build(precision: :high)
```

## Key Design Decisions

### 1. Singleton vs Temporary Instances
- **No args**: Returns singleton instance (cached)
- **With args**: Returns temporary instance (not cached)
- **Rationale**: Consistent API with always returning instances, args make caching complex

### 2. Dependency Resolution
- Dependencies are resolved regardless of arguments
- `@dependencies` remains static and argument-independent
- **Rationale**: Maintains core design principle of static dependency resolution

### 3. Return Values
- **No args**: `ProcessingTask.build` returns singleton instance 
- **With args**: `ProcessingTask.build(args)` returns temporary instance
- **Rationale**: Consistent API - always returns instance for symmetry

### 4. Exports Behavior
- Exports work on both singleton and temporary instances
- Each instance has its own `@exported_vars`
- **Rationale**: Allows flexible result access patterns

## Implementation Phases

### Phase 1: Core Implementation
1. Modify `build` method to accept arguments
2. Add `build_args` instance method
3. Implement temporary instance creation
4. Add basic tests

### Phase 2: Integration
1. Update logging to include arguments
2. Ensure dependency resolution works with arguments
3. Add comprehensive tests for edge cases
4. Update documentation

### Phase 3: Advanced Features
1. Consider argument validation
2. Add performance optimizations
3. Integration with execution tracking
4. Consider argument-aware caching strategies

## Backward Compatibility

Most existing functionality continues to work with minimal changes:
```ruby
# Return value changes from class to instance, but exports still work
instance = MyTask.build  # Returns instance instead of class
instance.some_exported_value  # Access via instance now
MyTask.clean  # Clean functionality unchanged
```

**Breaking change**: `build()` now returns instance instead of class.
**Migration**: Access exported values via returned instance instead of class.

## Testing Strategy

### Unit Tests
```ruby
def test_build_without_args_returns_singleton
  result = ProcessingTask.build
  assert_instance_of ProcessingTask, result
  assert_equal "default", result.result
  # Subsequent calls return same instance
  assert_equal result, ProcessingTask.build
end

def test_build_with_args_returns_temporary_instance
  instance = ProcessingTask.build(mode: :fast)
  assert_instance_of ProcessingTask, instance
  assert_equal "fast", instance.result
  # Different from singleton
  refute_equal instance, ProcessingTask.build
end

def test_dependencies_resolved_with_args
  instance = DependentTask.build(option: :value)
  # Dependencies should be built regardless of arguments
  assert BaseTask.built?
end
```

### Integration Tests
```ruby
def test_complex_parametrized_workflow
  # Test entire workflow with various argument combinations
end
```

## Future Considerations

1. **Argument Validation**: Type checking and required arguments
2. **Caching**: Argument-aware caching strategies
3. **Serialization**: Saving/loading parametrized results
4. **Parallel Execution**: Arguments in concurrent scenarios

## Benefits

1. **Flexibility**: Tasks can adapt behavior based on runtime needs
2. **Reusability**: Same task class, different configurations
3. **Simplicity**: Intuitive API that builds on existing patterns
4. **Compatibility**: Zero breaking changes to existing code
5. **Static Safety**: Dependencies remain statically analyzable