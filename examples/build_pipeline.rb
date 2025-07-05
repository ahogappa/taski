#!/usr/bin/env ruby

# Build Pipeline Example
# This example demonstrates a real-world CI/CD pipeline using all three APIs

require_relative "../lib/taski"

puts "=== Taski Build Pipeline Example ==="
puts

# Environment configuration using Define API
class Environment < Taski::Task
  define :is_ci, -> { ENV["CI"] == "true" }
  define :branch, -> { ENV["BRANCH"] || "main" }
  define :is_production, -> { branch == "main" && is_ci }
  define :parallel_jobs, -> { is_ci ? 4 : 2 }

  def run
    puts "Environment detected:"
    puts "  CI: #{is_ci}"
    puts "  Branch: #{branch}"
    puts "  Production deploy: #{is_production}"
    puts "  Parallel jobs: #{parallel_jobs}"
  end
end

# Source code preparation using Exports API
class SourceCode < Taski::Task
  exports :commit_hash, :version

  def run
    @commit_hash = `git rev-parse --short HEAD 2>/dev/null`.strip
    @commit_hash = "abc123" if @commit_hash.empty? # Fallback for demo

    # Version from git tags or fallback
    @version = `git describe --tags 2>/dev/null`.strip
    @version = "v1.0.0-dev" if @version.empty?

    puts "Source prepared:"
    puts "  Commit: #{@commit_hash}"
    puts "  Version: #{@version}"
  end
end

# Testing strategy using Section API
class TestingSection < Taski::Section
  interface :test_command, :coverage_threshold

  def impl
    Environment.is_ci ? CITesting : LocalTesting
  end

  class CITesting < Taski::Task
    def run
      @test_command = "rake test:ci"
      @coverage_threshold = 90
      puts "CI Testing configured:"
      puts "  Command: #{@test_command}"
      puts "  Coverage: #{@coverage_threshold}%"
    end
  end

  class LocalTesting < Taski::Task
    def run
      @test_command = "rake test"
      @coverage_threshold = 80
      puts "Local Testing configured:"
      puts "  Command: #{@test_command}"
      puts "  Coverage: #{@coverage_threshold}%"
    end
  end
end

# Build artifacts with mixed API usage
class BuildArtifacts < Taski::Task
  exports :artifact_path, :image_tag

  # Use define for dynamic values
  define :build_flags, -> {
    flags = ["--quiet"]
    flags << "--parallel #{Environment.parallel_jobs}"
    flags << "--optimize" if Environment.is_production
    flags.join(" ")
  }

  def run
    puts "Building artifacts..."
    puts "  Flags: #{build_flags}"

    # Simulate build process
    sleep(0.5)

    @artifact_path = "/tmp/app-#{SourceCode.version}-#{SourceCode.commit_hash}.tar.gz"
    @image_tag = "myapp:#{SourceCode.version}"

    puts "Artifacts created:"
    puts "  Archive: #{@artifact_path}"
    puts "  Image: #{@image_tag}"
  end
end

# Deployment strategy
class DeploymentSection < Taski::Section
  interface :deploy_target, :health_check_url

  def impl
    Environment.is_production ? ProductionDeploy : StagingDeploy
  end

  class ProductionDeploy < Taski::Task
    def run
      @deploy_target = "production.example.com"
      @health_check_url = "https://#{@deploy_target}/health"
      puts "Production deployment configured:"
      puts "  Target: #{@deploy_target}"
      puts "  Health check: #{@health_check_url}"
    end
  end

  class StagingDeploy < Taski::Task
    def run
      @deploy_target = "staging-#{Environment.branch}.example.com"
      @health_check_url = "https://#{@deploy_target}/health"
      puts "Staging deployment configured:"
      puts "  Target: #{@deploy_target}"
      puts "  Health check: #{@health_check_url}"
    end
  end
end

# Main pipeline orchestrator
class Pipeline < Taski::Task
  def run
    puts "\n🚀 Starting CI/CD Pipeline"
    puts "Version: #{SourceCode.version} (#{SourceCode.commit_hash})"

    # 1. Run tests
    puts "\n📋 Running tests..."
    puts "Command: #{TestingSection.test_command}"
    puts "Required coverage: #{TestingSection.coverage_threshold}%"
    sleep(0.3) # Simulate test execution

    # 2. Build artifacts
    puts "\n🔨 Building application..."
    artifact = BuildArtifacts.artifact_path
    image = BuildArtifacts.image_tag
    puts "Created: #{File.basename(artifact)}"
    puts "Tagged: #{image}"

    # 3. Deploy
    puts "\n🚢 Deploying application..."
    puts "Target: #{DeploymentSection.deploy_target}"
    sleep(0.2) # Simulate deployment

    # 4. Health check
    puts "\n❤️ Running health checks..."
    puts "Checking: #{DeploymentSection.health_check_url}"
    sleep(0.1)

    puts "\n✅ Pipeline completed successfully!"
  end
end

# Demonstrate different scenarios
puts "Scenario 1: Local development build"
ENV["CI"] = "false"
ENV["BRANCH"] = "feature/new-api"
Pipeline.run

puts "\n" + "=" * 60 + "\n"

puts "Scenario 2: CI staging build"
ENV["CI"] = "true"
ENV["BRANCH"] = "staging"
Pipeline.reset! # Reset to re-evaluate all define blocks
Pipeline.run

puts "\n" + "=" * 60 + "\n"

puts "Scenario 3: Production deployment"
ENV["CI"] = "true"
ENV["BRANCH"] = "main"
Pipeline.reset!
Pipeline.run

puts "\n" + "=" * 60 + "\n"

# Show the complete dependency graph
puts "Complete Pipeline Dependency Tree:"
puts Pipeline.tree

puts "\nPipeline Benefits:"
puts "- Environment-aware configuration (Define API)"
puts "- Reliable static values (Exports API)"
puts "- Environment-specific implementations (Section API)"
puts "- Automatic dependency resolution"
puts "- Visual progress tracking"
puts "- Reproducible builds"
