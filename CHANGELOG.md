# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.8.1] - 2026-01-26

### Added
- `Taski.message` API for user-facing output during task execution ([#129](https://github.com/ahogappa/taski/pull/129))

### Fixed
- Count unselected section candidates as completed in SimpleProgressDisplay ([#128](https://github.com/ahogappa/taski/pull/128))
- Prioritize environment variable over code settings for progress_mode ([#127](https://github.com/ahogappa/taski/pull/127))

## [0.8.0] - 2026-01-23

### Added
- `Taski::Env` class for system-managed execution environment information ([#125](https://github.com/ahogappa/taski/pull/125))
  - Access via `Taski.env.working_directory`, `Taski.env.started_at`, `Taski.env.root_task`
- `args` and `workers` parameters to `Task.new` for direct task instantiation ([#125](https://github.com/ahogappa/taski/pull/125))
- `mock_env` helper in `TestHelper` for mocking environment in tests ([#125](https://github.com/ahogappa/taski/pull/125))

### Changed
- Separate system attributes from `Taski.args` to `Taski.env` ([#125](https://github.com/ahogappa/taski/pull/125))
  - `Taski.args` now holds only user-defined options passed via `run(args: {...})`
  - `Taski.env` holds system-managed execution environment (`root_task`, `started_at`, `working_directory`)

## [0.7.1] - 2026-01-22

### Added
- `Taski::TestHelper` module for mocking task dependencies in unit tests ([#123](https://github.com/ahogappa/taski/pull/123))
  - `mock_task(TaskClass, key: value)` to mock exported values without running tasks
  - `assert_task_accessed` / `refute_task_accessed` for verifying dependency access
  - Support for both Minitest and RSpec test frameworks
- Simple one-line progress display mode (`Taski.progress_mode = :simple`) as an alternative to tree display ([#112](https://github.com/ahogappa/taski/pull/112))
  - Configure via `TASKI_PROGRESS_MODE` environment variable or `Taski.progress_mode` API
- Display captured task output (up to 30 lines) in AggregateError messages for better debugging ([#109](https://github.com/ahogappa/taski/pull/109))
- Background polling thread in TaskOutputRouter to ensure pipes are drained reliably ([#122](https://github.com/ahogappa/taski/pull/122))
- `Taski.with_args` helper method for safe argument lifecycle management ([#110](https://github.com/ahogappa/taski/pull/110))

### Changed
- Progress display now uses alternate screen buffer and shows summary line after completion ([#107](https://github.com/ahogappa/taski/pull/107))
- Eliminate screen flickering in tree progress display with in-place overwrite rendering ([#121](https://github.com/ahogappa/taski/pull/121))
- Extract `BaseProgressDisplay` class for shared progress display functionality ([#117](https://github.com/ahogappa/taski/pull/117))

### Fixed
- Wait for running dependencies in nested executor to prevent deadlock ([#106](https://github.com/ahogappa/taski/pull/106))
- Preserve namespace path when following method calls in static analysis ([#108](https://github.com/ahogappa/taski/pull/108))
- Prevent race condition in `Taski.args` lifecycle during concurrent execution ([#110](https://github.com/ahogappa/taski/pull/110))
- Ensure progress display cleanup on interrupt (Ctrl+C) ([#107](https://github.com/ahogappa/taski/pull/107))
- Always enable output in PlainProgressDisplay ([#117](https://github.com/ahogappa/taski/pull/117))

## [0.7.0] - 2025-12-23

### Added
- Group block for organizing progress display messages (`Taski.group`) ([#105](https://github.com/ahogappa/taski/pull/105))
- Scope-based execution with thread-local registry for independent task execution ([#103](https://github.com/ahogappa/taski/pull/103))
- `TaskClass::Error` auto-generation for task-specific error handling ([#95](https://github.com/ahogappa/taski/pull/95))
- `AggregateAware` module for transparent rescue matching with `AggregateError` ([#95](https://github.com/ahogappa/taski/pull/95))
- `AggregateError#includes?` and `AggregateError#find` methods for searching aggregated errors ([#95](https://github.com/ahogappa/taski/pull/95))
- Aggregation of multiple errors in parallel execution ([#95](https://github.com/ahogappa/taski/pull/95))
- `workers` parameter to `Task.run`, `Task.clean`, and `Task.run_and_clean` for configurable parallelism ([#92](https://github.com/ahogappa/taski/pull/92))

### Changed
- Renamed `context` to `args` for API clarity (BREAKING CHANGE) ([#94](https://github.com/ahogappa/taski/pull/94))

### Fixed
- Thread-safety improvements in `Registry#get_or_create` ([#90](https://github.com/ahogappa/taski/pull/90))

## [0.6.0] - 2025-12-21

### Added
- `Task#system` override for capturing subprocess output in progress display
- `ExecutionContext` with observer pattern for managing execution state
- Inline task output display in progress tree
- Clean execution with reverse dependency order via `run_and_clean`
- Comprehensive documentation for `TaskAbortException`
- Unit tests for `ExecutionContext`, `WorkerPool`, and `Scheduler`

### Changed
- Replaced `ThreadOutputCapture` with pipe-based `TaskOutputRouter` for more reliable output capture
- Split `Executor` into separate `Scheduler` and `WorkerPool` classes for better separation of concerns
- Centralized tree building logic in `TreeProgressDisplay`
- Improved `run_and_clean` implementation and display

### Fixed
- Added mutex protection to `impl_call_order` accessor for thread safety
- Fixed `ExecutionContext` passing to `TaskWrapper` resolving progress display garbage
- Improved output capture reliability for progress display

## [0.5.0] - 2025-11-30

- Initial release with core task execution functionality
