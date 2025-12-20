# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
