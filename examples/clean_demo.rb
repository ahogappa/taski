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

  def run
    @build_path = "#{BUILD_DIR}/build"
    puts "[SetupBuildDir] Creating build directory: #{@build_path}"
    # Simulated directory creation
    sleep 0.8
  end

  def clean
    puts "[SetupBuildDir] Removing build directory: #{@build_path}"
    # Simulated directory removal
    sleep 0.8
  end
end

# Compiles source code (depends on build directory)
class CompileSource < Taski::Task
  exports :binary_path

  def run
    build_dir = SetupBuildDir.build_path
    @binary_path = "#{build_dir}/app.bin"
    puts "[CompileSource] Compiling to: #{@binary_path}"
    sleep 1.5
  end

  def clean
    puts "[CompileSource] Removing compiled binary: #{@binary_path}"
    sleep 0.6
  end
end

# Generates documentation (depends on build directory)
class GenerateDocs < Taski::Task
  exports :docs_path

  def run
    build_dir = SetupBuildDir.build_path
    @docs_path = "#{build_dir}/docs"
    puts "[GenerateDocs] Generating docs to: #{@docs_path}"
    sleep 1.2
  end

  def clean
    puts "[GenerateDocs] Removing generated docs: #{@docs_path}"
    sleep 0.5
  end
end

# Creates release package (depends on both compiled source and docs)
class CreateRelease < Taski::Task
  exports :release_path

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
