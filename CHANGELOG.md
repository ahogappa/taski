# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
