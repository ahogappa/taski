#!/usr/bin/env ruby
# frozen_string_literal: true

# Taski Clean Demo
#
# This example demonstrates the clean functionality:
# - Defining clean methods for resource cleanup
# - Reverse dependency order execution (dependents cleaned before dependencies)
# - run_and_clean with block support
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
    sleep 0.8
  end

  def clean
    puts "[SetupBuildDir] Removing build directory: #{@build_path}"
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

puts "--- run_and_clean Demo ---"
puts "The run_and_clean method executes both phases in a single operation."
puts "Key benefits:"
puts "  - Single progress display session for both phases"
puts "  - Clean always runs, even if run fails (resource release)"
puts "  - Cleaner API for the common use case"
puts

CreateRelease.run_and_clean

puts
puts "Both run and clean phases completed in a single call!"
puts

# Demonstrate block support
Taski::Task.reset!

puts "=" * 40
puts "run_and_clean with Block Demo"
puts "=" * 40
puts
puts "Use a block to execute code between run and clean phases."
puts "Exported values are accessible within the block."
puts

CreateRelease.run_and_clean do
  puts
  puts "[Block] Release created at: #{CreateRelease.release_path}"
  puts "[Block] Binary: #{CompileSource.binary_path}"
  puts "[Block] Docs: #{GenerateDocs.docs_path}"
  puts "[Block] Deploying release..."
  sleep 0.3
  puts "[Block] Deploy complete!"
  puts
end

puts
puts "Block executed between run and clean phases!"
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
