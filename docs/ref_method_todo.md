# ref Method Implementation TODO

## Overview

The `ref` method is designed to enable forward declarations in define API while maintaining the core design principle: **"All task dependencies must be statically resolvable and known before execution"**.

### Design Principle
- `@dependencies` must contain ALL task classes that this task depends on
- Dependencies are resolved statically during class definition
- Execution tracking and rollback can rely solely on `@dependencies` 
- No dynamic dependency discovery during runtime

## Current Status

### ✅ Completed
- Modified `ref` method to use `throw :unresolved` during dependency analysis
- Added Reference object support in reset processing  
- Basic tests pass without infinite loops
- Committed initial implementation (commit: 9b9f91e)

### 🚧 Known Issues
1. **Forward declaration not fully working** - Complex tests disabled due to potential infinite loops
2. **Reference object handling incomplete** - May need additional processing in dependency resolution
3. **Error handling needs improvement** - Non-existent class resolution at runtime

## Implementation Details

### Current ref Method Logic
```ruby
def ref(klass_name)
  if Thread.current[TASKI_ANALYZING_DEFINE_KEY]
    # During analysis: create Reference and track dependency
    reference = Taski::Reference.new(klass_name)
    throw :unresolved, [reference, :deref]
  else
    # At runtime: resolve to actual class
    Object.const_get(klass_name)
  end
end
```

### Problem Areas
1. **Reset processing** - Reference objects don't have `@__resolve__` state
2. **Dependency resolution** - May need special handling for Reference objects
3. **Circular dependency detection** - Should work with Reference objects

## Test Cases to Implement

### 1. Basic Dependency Tracking
```ruby
task_b = Class.new(Taski::Task) do
  define :result, -> { ref("TaskA").data }
end

# Should include Reference("TaskA") in dependencies
assert_includes dependencies, Reference("TaskA")
```

### 2. Forward Declaration
```ruby
# Define in reverse order: C -> B -> A
class TaskC < Taski::Task
  define :result, -> { ref("TaskB").intermediate }
end

class TaskB < Taski::Task  
  define :intermediate, -> { ref("TaskA").base }
end

class TaskA < Taski::Task
  exports :base
end

# Should work despite definition order
TaskC.result  # => Success
```

### 3. Error Handling
```ruby
class ErrorTask < Taski::Task
  define :result, -> { ref("NonExistentTask").method }
end

# Should raise NameError at runtime, not definition time
assert_raises(NameError) { ErrorTask.result }
```

## Implementation Plan

### Phase 1: Fix Core Issues
1. Debug infinite loop in dependency analysis
2. Ensure Reference objects are properly handled in reset
3. Verify basic ref functionality works

### Phase 2: Complete Forward Declaration
1. Enable complex test cases
2. Test reverse definition order scenarios
3. Verify dependency graph construction

### Phase 3: Error Handling
1. Improve non-existent class error messages
2. Add proper error handling in dependency resolution
3. Test edge cases and error conditions

### Phase 4: Integration
1. Integrate with execution tracking system
2. Ensure compatibility with rollback functionality
3. Update documentation and examples

## Notes

- The ref method is crucial for enabling flexible task definition patterns
- Forward declaration is especially important for large task graphs
- This feature should maintain backward compatibility with existing code
- Consider performance implications of deferred resolution

## Related Files
- `lib/taski/task/define_api.rb` - Main implementation
- `test/test_reference.rb` - Test cases
- `lib/taski/reference.rb` - Reference class