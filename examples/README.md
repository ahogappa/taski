# Taski Examples

Learn Taski through practical examples demonstrating parallel execution and automatic dependency resolution.

## 🚀 Learning Path

Follow these examples in order for the best learning experience:

### 1. **[quick_start.rb](quick_start.rb)** - Exports API Basics ⭐
Your first Taski program demonstrating:
- Static dependencies with `exports`
- Automatic dependency resolution
- Basic task execution

```bash
ruby examples/quick_start.rb
```

**What you'll learn:**
- How to define tasks with `exports`
- How dependencies are automatically resolved
- How to access exported values from other tasks

---

### 2. **[section_basics.rb](section_basics.rb)** - Runtime Implementation Selection ⭐⭐
Environment-specific implementations using the Section API:
- Switch implementations based on environment
- Clean interface definitions
- Dependency tree visualization

```bash
ruby examples/section_basics.rb
```

**What you'll learn:**
- How to use `interfaces` to define contracts
- How to implement environment-specific behavior
- How to visualize dependency trees with `.tree`

---

### 3. **[parallel_progress_demo.rb](parallel_progress_demo.rb)** - Parallel Execution with Progress Display ⭐⭐⭐
Real-time progress visualization of parallel task execution:
- Docker-style multi-layer download simulation
- Parallel execution of independent tasks
- Real-time progress with timing

```bash
# Enable progress display
TASKI_FORCE_PROGRESS=1 ruby examples/parallel_progress_demo.rb
```

**What you'll learn:**
- How tasks execute in parallel automatically
- How to enable and use progress display
- How execution timing works in parallel scenarios

---

## 📚 What You'll Learn

### Core APIs
- **Exports API**: Share computed values between tasks
- **Section API**: Runtime implementation selection based on environment

### Key Features
- **Parallel Execution**: Independent tasks run concurrently using threads
- **Static Analysis**: Dependencies detected automatically via Prism AST
- **Progress Display**: Real-time visual feedback with spinners and timing
- **Thread-Safe**: Monitor-based synchronization for reliable concurrent execution

### Real-World Applications
- **Configuration Management**: Environment-specific settings
- **Build Pipelines**: Parallel compilation and testing
- **Service Orchestration**: Microservice dependency management
- **Data Processing**: Parallel ETL workflows

## 🎯 Quick Reference

| Example | Primary Feature | Complexity | Run Time |
|---------|----------------|------------|----------|
| quick_start | Exports API | ⭐ | < 1s |
| section_basics | Section API | ⭐⭐ | < 1s |
| parallel_progress_demo | Parallel Execution | ⭐⭐⭐ | ~2s |

## 🔗 Next Steps

After completing these examples:
- **[Main README](../README.md)**: Full project documentation
- **[Tests](../test/)**: Explore the test suite for more patterns
- **[Source Code](../lib/taski/)**: Dive into the implementation
  - `lib/taski/task.rb` - Core Task implementation
  - `lib/taski/section.rb` - Section API
  - `lib/taski/execution/` - Parallel execution engine
  - `lib/taski/static_analysis/` - Dependency analyzer

## 💡 Tips for Learning

1. **Start Simple**: Begin with `quick_start.rb` even if you're experienced
2. **Experiment**: Modify the examples to see how behavior changes
3. **Use Progress Display**: Set `TASKI_FORCE_PROGRESS=1` to see real-time execution
4. **Visualize Dependencies**: Use `.tree` method to see task relationships
5. **Read Source Code**: Examples are heavily commented for learning

## 🎨 Example Patterns

### Basic Task Pattern
```ruby
class MyTask < Taski::Task
  exports :result

  def run
    @result = compute_something()
  end
end
```

### Section Pattern
```ruby
class MySection < Taski::Section
  interfaces :value

  def impl
    ENV['PROD'] ? ProdImpl : DevImpl
  end

  class ProdImpl < Taski::Task
    exports :value
    def run; @value = "prod"; end
  end
end
```

### Dependency Pattern
```ruby
class Consumer < Taski::Task
  def run
    # Automatically depends on Producer
    puts Producer.data
  end
end
```

---

**Happy Learning!** 🚀
