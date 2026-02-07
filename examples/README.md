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

### 2. args_demo.rb - Runtime Args and Options

Access execution args and pass custom options to tasks.

```bash
ruby examples/args_demo.rb
```

**Covers:**
- User-defined options via `run(args: {...})`
- `Taski.args[:key]` for option access
- `Taski.args.fetch(:key, default)` for defaults
- `Taski.env.working_directory`
- `Taski.env.started_at`
- `Taski.env.root_task`

---

### 3. reexecution_demo.rb - Scope-Based Execution

Understand scope-based execution and caching behavior.

```bash
ruby examples/reexecution_demo.rb
```

**Covers:**
- Fresh execution for each class method call
- Instance-level caching with `Task.new`
- Scope-based dependency caching

---

### 4. clean_demo.rb - Lifecycle Management

Demonstrates resource cleanup with clean methods.

```bash
ruby examples/clean_demo.rb
```

**Covers:**
- Defining `clean` methods for resource cleanup
- Reverse dependency order execution
- `run_and_clean` combined operation

---

### 5. group_demo.rb - Task Output Grouping

Organize task output into logical phases with groups.

```bash
ruby examples/group_demo.rb
```

**Covers:**
- `group("label") { ... }` for organizing output
- Groups displayed as children in progress tree
- Multiple groups within a single task

---

### 6. message_demo.rb - User-Facing Messages

Output messages that bypass the progress display capture.

```bash
ruby examples/message_demo.rb
```

**Covers:**
- `Taski.message(text)` for user-facing output
- Messages queued during progress and shown after completion
- Difference between `puts` (captured) and `Taski.message` (bypassed)

---

### 7. progress_demo.rb - Progress Display Modes

Real-time progress visualization during parallel execution.

```bash
ruby examples/progress_demo.rb   # Simple mode (default)
```

**Covers:**
- Tree progress display (default)
- Simple one-line progress display
- Parallel task execution
- Task output capture and streaming
- system() output integration

---

## Quick Reference

| Example | Feature | Complexity |
|---------|---------|------------|
| quick_start | Exports API | Basic |
| args_demo | Args/Env API | Intermediate |
| reexecution_demo | Scope-Based Execution | Intermediate |
| clean_demo | Lifecycle Management | Intermediate |
| group_demo | Output Grouping | Intermediate |
| message_demo | User Messages | Basic |
| progress_demo | Progress Display | Advanced |

## Running All Examples

```bash
# Run each example
for f in examples/*.rb; do echo "=== $f ===" && ruby "$f" && echo; done

# Disable progress display if needed (add Taski.progress_display = nil in script)
```

## Next Steps

- [Main README](../README.md) - Full documentation
- [Tests](../test/) - More usage patterns
- [Source](../lib/taski/) - Implementation details
