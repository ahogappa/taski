#!/usr/bin/env ruby
# frozen_string_literal: true

# Taski Clean Demo
#
# This example demonstrates the clean functionality:
# - Defining clean methods for resource cleanup
# - Reverse dependency order execution (dependents cleaned before dependencies)
# - Parallel clean execution when possible
#
# Run: ruby examples/clean_demo.rb

require_relative "../lib/taski"

puts "Taski Clean Demo"
puts "=" * 40

# Simulated build artifact paths
BUILD_DIR = "/tmp/taski_clean_demo"

# Base task: creates a build directory
class SetupBuildDir < Taski::Task
  exports :build_path

  ##
  # Prepares the task's build directory and simulates its creation.
  #
  # Sets the task's exported `build_path` to the "build" subdirectory under `BUILD_DIR`
  # and performs a simulated creation step with informational output.
  def run
    @build_path = "#{BUILD_DIR}/build"
    puts "[SetupBuildDir] Creating build directory: #{@build_path}"
    # Simulated directory creation
    sleep 0.8
  end

  ##
  # Removes the directory referenced by @build_path.
  # Cleans up build artifacts created by this task.
  def clean
    puts "[SetupBuildDir] Removing build directory: #{@build_path}"
    # Simulated directory removal
    sleep 0.8
  end
end

# Compiles source code (depends on build directory)
class CompileSource < Taski::Task
  exports :binary_path

  ##
  # Compiles source artifacts and sets the compiled binary path for downstream tasks.
  # This method sets @binary_path to the build directory's "app.bin" file and emits a console message indicating the compilation target.
  def run
    build_dir = SetupBuildDir.build_path
    @binary_path = "#{build_dir}/app.bin"
    puts "[CompileSource] Compiling to: #{@binary_path}"
    sleep 1.5
  end

  ##
  # Removes the compiled binary produced by this task.
  # Performs the task's cleanup step and simulates the deletion process.
  def clean
    puts "[CompileSource] Removing compiled binary: #{@binary_path}"
    sleep 0.6
  end
end

# Generates documentation (depends on build directory)
class GenerateDocs < Taski::Task
  exports :docs_path

  ##
  # Generates documentation for the build and records the output path.
  #
  # Sets the task's `@docs_path` to the "docs" subdirectory under `SetupBuildDir.build_path`
  # and prints a progress message to STDOUT.
  def run
    build_dir = SetupBuildDir.build_path
    @docs_path = "#{build_dir}/docs"
    puts "[GenerateDocs] Generating docs to: #{@docs_path}"
    sleep 1.2
  end

  ##
  # Removes the generated documentation at the task's docs_path.
  # Prints a removal message for @docs_path and simulates its deletion.
  def clean
    puts "[GenerateDocs] Removing generated docs: #{@docs_path}"
    sleep 0.5
  end
end

# Creates release package (depends on both compiled source and docs)
class CreateRelease < Taski::Task
  exports :release_path

  ##
  # Creates the release package path and announces the included artifacts.
  # Uses CompileSource.binary_path and GenerateDocs.docs_path to determine the package inputs, sets @release_path to "#{BUILD_DIR}/release.zip", and prints the binary, docs, and output paths.
  def run
    binary = CompileSource.binary_path
    docs = GenerateDocs.docs_path
    @release_path = "#{BUILD_DIR}/release.zip"
    puts "[CreateRelease] Creating release package with:"
    puts "  - Binary: #{binary}"
    puts "  - Docs: #{docs}"
    puts "  - Output: #{@release_path}"
    sleep 0.7
  end

  ##
  # Removes the release package produced by this task.
  # Uses the task's `@release_path` as the target for cleanup.
  def clean
    puts "[CreateRelease] Removing release package: #{@release_path}"
    sleep 0.5
  end
end

puts "\n--- Task Tree Structure ---"
puts CreateRelease.tree
puts

puts "--- Running build process ---"
CreateRelease.run
puts

puts "Build completed!"
puts "  Release: #{CreateRelease.release_path}"
puts

puts "--- Cleaning up (reverse dependency order) ---"
puts "Note: CreateRelease cleans first, then CompileSource/GenerateDocs in parallel,"
puts "      and finally SetupBuildDir cleans last."
puts

# Reset to allow clean execution
Taski::Task.reset!

# Re-run to set up state for clean
CreateRelease.run

puts "\nNow cleaning..."
CreateRelease.clean

puts
puts "Clean completed! All artifacts removed."

puts
puts "=" * 40
puts "run_and_clean Demo"
puts "=" * 40
puts
puts "The run_and_clean method executes both phases in a single operation."
puts "Key benefits:"
puts "  - Single progress display session for both phases"
puts "  - Clean always runs, even if run fails (resource release)"
puts "  - Cleaner API for the common use case"
puts

# Reset for new demonstration
Taski::Task.reset!

puts "--- Using run_and_clean ---"
puts "This is equivalent to calling run followed by clean, but in a single operation."
puts

CreateRelease.run_and_clean

puts
puts "Both run and clean phases completed in a single call!"
puts

# Demonstrate error handling
Taski::Task.reset!

puts "--- Error Handling Demo ---"
puts "When run fails, clean is still executed for resource release."
puts

# Task that fails during run
class FailingBuild < Taski::Task
  exports :result

  def run
    puts "[FailingBuild] Starting build..."
    raise StandardError, "Build failed: missing dependencies"
  end

  def clean
    puts "[FailingBuild] Cleaning up partial build artifacts..."
  end
end

begin
  FailingBuild.run_and_clean
rescue => e
  puts "[Error caught] #{e.message}"
end

puts
puts "Notice: clean was still executed despite run failing!"
