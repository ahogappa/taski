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

### 3. context_demo.rb - Runtime Context and Options

Access execution context and pass custom options to tasks.

```bash
ruby examples/context_demo.rb
```

**Covers:**
- User-defined options via `run(context: {...})`
- `Taski.context[:key]` for option access
- `Taski.context.fetch(:key, default)` for defaults
- `Taski.context.working_directory`
- `Taski.context.started_at`
- `Taski.context.root_task`

---

### 4. reexecution_demo.rb - Cache Control

Understand caching behavior and re-execution patterns.

```bash
ruby examples/reexecution_demo.rb
```

**Covers:**
- Default caching behavior
- `Task.new` for fresh instances
- `Task.reset!` for clearing caches

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
TASKI_FORCE_PROGRESS=1 ruby examples/parallel_progress_demo.rb
```

**Covers:**
- Parallel task execution
- Progress display with spinners
- Execution timing

---

## Quick Reference

| Example | Feature | Complexity |
|---------|---------|------------|
| quick_start | Exports API | Basic |
| section_demo | Section API | Intermediate |
| context_demo | Context API | Intermediate |
| reexecution_demo | Cache Control | Intermediate |
| data_pipeline_demo | ETL Pipeline | Advanced |
| parallel_progress_demo | Progress Display | Advanced |

## Running All Examples

```bash
# Run each example
for f in examples/*.rb; do echo "=== $f ===" && ruby "$f" && echo; done

# With progress display (for parallel_progress_demo)
TASKI_FORCE_PROGRESS=1 ruby examples/parallel_progress_demo.rb
```

## Next Steps

- [Main README](../README.md) - Full documentation
- [Tests](../test/) - More usage patterns
- [Source](../lib/taski/) - Implementation details
