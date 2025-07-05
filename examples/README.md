# Taski Examples

Learn Taski through practical examples, from basic concepts to real-world applications.

## 🚀 Learning Path

Follow these examples in order for the best learning experience:

### 1. **[quick_start.rb](quick_start.rb)** - Exports API Basics
- Your first Taski program
- Static dependencies with `exports`
- Automatic dependency resolution

```bash
ruby examples/quick_start.rb
```

### 2. **[define_api_basics.rb](define_api_basics.rb)** - Dynamic Dependencies
- Environment-based logic with Define API
- Runtime value computation
- When to use Define vs Exports

```bash
ruby examples/define_api_basics.rb
```

### 3. **[section_basics.rb](section_basics.rb)** - Implementation Selection
- Environment-specific implementations
- Clean interfaces with Section API
- Dependency tree visualization

```bash
ruby examples/section_basics.rb
```

### 4. **[progress_demo.rb](progress_demo.rb)** - Visual Progress
- Animated progress display
- Output capture and timing
- TTY detection for logging

```bash
# Interactive mode with spinner
ruby examples/progress_demo.rb

# Clean output for logging
ruby examples/progress_demo.rb > build.log 2>&1
```

### 5. **[build_pipeline.rb](build_pipeline.rb)** - Real-World Pipeline
- Complete CI/CD workflow example
- Mixed API usage patterns
- Production-ready error handling

```bash
ruby examples/build_pipeline.rb
```

### 6. **[error_handling.rb](error_handling.rb)** - Robust Error Management
- Dependency error recovery
- Graceful degradation patterns
- Signal interruption handling

```bash
ruby examples/error_handling.rb
```

### 7. **[advanced_patterns.rb](advanced_patterns.rb)** - Complex Scenarios
- Advanced dependency patterns
- Performance optimization
- Custom logging strategies

```bash
ruby examples/advanced_patterns.rb
```

## 📚 What You'll Learn

### Core APIs
- **Exports API**: Static values with side effects
- **Define API**: Dynamic computation without side effects
- **Section API**: Runtime implementation selection

### Advanced Features
- **Progress Display**: Visual feedback and timing
- **Error Recovery**: Fallback strategies and graceful failures
- **Signal Handling**: Interruption and cleanup
- **Logging**: Structured output and monitoring

### Real-World Applications
- **Build Pipelines**: CI/CD workflows
- **Configuration Management**: Environment-specific settings
- **Service Orchestration**: Microservice dependencies
- **Data Processing**: ETL and transformation pipelines

## 🎯 Quick Reference

| Example | Primary API | Complexity | Use Case |
|---------|-------------|------------|----------|
| quick_start | Exports | ⭐ | First steps |
| define_api_basics | Define | ⭐⭐ | Dynamic values |
| section_basics | Section | ⭐⭐ | Implementation choice |
| progress_demo | All | ⭐⭐ | Visual feedback |
| build_pipeline | Mixed | ⭐⭐⭐ | CI/CD workflows |
| error_handling | Mixed | ⭐⭐⭐ | Production robustness |
| advanced_patterns | Mixed | ⭐⭐⭐⭐ | Complex scenarios |

## 🔗 Next Steps

After completing these examples:
- **[API Guide](../docs/api-guide.md)**: Detailed API documentation
- **[Advanced Features](../docs/advanced-features.md)**: In-depth feature guides
- **[Error Handling](../docs/error-handling.md)**: Comprehensive error strategies
- **[Tests](../test/)**: Explore the test suite for more patterns
- **[Source Code](../lib/taski/)**: Dive into the implementation

## 💡 Tips for Learning

1. **Start Simple**: Begin with `quick_start.rb` even if you're experienced
2. **Experiment**: Modify the examples to see how behavior changes
3. **Read Output**: Pay attention to progress display and timing information
4. **Check Dependencies**: Use `.tree` method to visualize task relationships
5. **Test Errors**: Try breaking examples to understand error handling