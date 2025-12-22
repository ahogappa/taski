# Taski Examples

Practical examples demonstrating Taski's parallel task execution and automatic dependency resolution.

## Examples

### 1. quick_start.rb - Getting Started

Basic Exports API usage and automatic dependency resolution.

```bash
ruby examples/quick_start.rb
```

**Covers:**
- Task definition with `exports`
- Automatic dependency detection
- Accessing exported values

---

### 2. section_demo.rb - Runtime Implementation Selection

Switch implementations based on environment using the Section API.

```bash
ruby examples/section_demo.rb
```

**Covers:**
- `interfaces` for defining contracts
- Environment-specific implementations
- Dependency tree visualization with `.tree`

---

### 3. context_demo.rb - Runtime Args and Options

Access execution args and pass custom options to tasks.

```bash
ruby examples/context_demo.rb
```

**Covers:**
- User-defined options via `run(args: {...})`
- `Taski.args[:key]` for option access
- `Taski.args.fetch(:key, default)` for defaults
- `Taski.args.working_directory`
- `Taski.args.started_at`
- `Taski.args.root_task`

---

### 4. reexecution_demo.rb - Scope-Based Execution

Understand scope-based execution and caching behavior.

```bash
TASKI_PROGRESS_DISABLE=1 ruby examples/reexecution_demo.rb
```

**Covers:**
- Fresh execution for each class method call
- Instance-level caching with `Task.new`
- Scope-based dependency caching

---

### 5. data_pipeline_demo.rb - Real-World Pipeline

A realistic ETL pipeline with parallel data fetching.

```bash
ruby examples/data_pipeline_demo.rb
```

**Covers:**
- Multiple data sources in parallel
- Data transformation stages
- Aggregation and reporting

---

### 6. parallel_progress_demo.rb - Progress Display

Real-time progress visualization during parallel execution.

```bash
ruby examples/parallel_progress_demo.rb
```

**Covers:**
- Parallel task execution
- Progress display with spinners
- Execution timing

---

### 7. clean_demo.rb - Lifecycle Management

Demonstrates resource cleanup with clean methods.

```bash
ruby examples/clean_demo.rb
```

**Covers:**
- Defining `clean` methods for resource cleanup
- Reverse dependency order execution
- `run_and_clean` combined operation

---

### 8. system_call_demo.rb - Subprocess Output

Capture subprocess output in progress display.

```bash
ruby examples/system_call_demo.rb
```

**Covers:**
- `system()` output capture
- Streaming output display
- Parallel subprocess execution

---

### 9. nested_section_demo.rb - Nested Sections

Sections that depend on other tasks for implementation selection.

```bash
TASKI_PROGRESS_DISABLE=1 ruby examples/nested_section_demo.rb
```

**Covers:**
- Section inside Section
- Dynamic implementation selection
- Complex dependency hierarchies

---

## Quick Reference

| Example | Feature | Complexity |
|---------|---------|------------|
| quick_start | Exports API | Basic |
| section_demo | Section API | Intermediate |
| context_demo | Args API | Intermediate |
| reexecution_demo | Scope-Based Execution | Intermediate |
| data_pipeline_demo | ETL Pipeline | Advanced |
| parallel_progress_demo | Progress Display | Advanced |
| clean_demo | Lifecycle Management | Intermediate |
| system_call_demo | Subprocess Output | Advanced |
| nested_section_demo | Nested Sections | Advanced |

## Running All Examples

```bash
# Run each example
for f in examples/*.rb; do echo "=== $f ===" && ruby "$f" && echo; done

# Disable progress display if needed
TASKI_PROGRESS_DISABLE=1 ruby examples/parallel_progress_demo.rb
```

## Next Steps

- [Main README](../README.md) - Full documentation
- [Tests](../test/) - More usage patterns
- [Source](../lib/taski/) - Implementation details
