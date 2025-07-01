# Taski Examples

Learn Taski through practical examples, from basic concepts to advanced patterns.

## Getting Started

Start with these examples in order:

### 1. **[quick_start.rb](quick_start.rb)** - Your First Taski Program
- Basic task definition with Exports API
- Automatic dependency resolution
- Simple task execution

```bash
ruby examples/quick_start.rb
```

### 2. **[progress_demo.rb](progress_demo.rb)** - Rich CLI Progress Display
- Animated spinner with ANSI colors
- Real-time output capture and 5-line tail
- Production build scenarios
- TTY detection for clean file output

```bash
# Interactive mode with rich spinner
ruby examples/progress_demo.rb

# Clean output mode (no spinner)
ruby examples/progress_demo.rb > build.log 2>&1
cat build.log
```

### 3. **[section_configuration.rb](section_configuration.rb)** - Section-based Configuration Management
- Dynamic implementation selection with Taski::Section
- Environment-specific configuration
- Section dependency resolution
- Complex configuration hierarchies

```bash
ruby examples/section_configuration.rb
```

### 4. **[advanced_patterns.rb](advanced_patterns.rb)** - Complex Dependency Patterns
- Mixed Exports API and Define API usage
- Environment-specific dependencies
- Feature flags and conditional logic
- Task reset and rebuild scenarios

```bash
ruby examples/advanced_patterns.rb
```

## Key Concepts Demonstrated

- **Exports API**: Static dependencies with `exports :property`
- **Define API**: Dynamic dependencies with `define :property, -> { ... }`
- **Section API**: Dynamic implementation selection with `Taski::Section`
- **Dependency Resolution**: Automatic dependency detection for sections
- **Progress Display**: Rich terminal output with spinners and colors
- **Output Capture**: Tail-style display of task output
- **Environment Configuration**: Different behavior based on runtime settings
- **Error Handling**: Graceful failure with progress indicators

## Next Steps

After exploring these examples:
- Read the main documentation
- Examine the test files for more usage patterns
- Check out the source code in `lib/taski/`