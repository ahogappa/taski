#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/taski"

# Large tree demo script for testing progress display with 50+ tasks
# Run with: TASKI_FORCE_PROGRESS=1 ruby examples/large_tree_demo.rb
#
# This demo creates a realistic task tree with:
# - 50+ tasks total
# - Nested dependencies (tree depth 4+)
# - Varying execution times (50ms - 2000ms)
# - Some tasks that fail (to verify error visibility)
# - Tasks that produce output

# Level 4: Leaf tasks (no dependencies)
class FetchConfigA < Taski::Task
  exports :config_a

  def run
    puts "Fetching config A..."
    sleep(0.1)
    @config_a = {server: "localhost", port: 3000}
  end
end

class FetchConfigB < Taski::Task
  exports :config_b

  def run
    puts "Fetching config B..."
    sleep(0.15)
    @config_b = {timeout: 30, retries: 3}
  end
end

class FetchConfigC < Taski::Task
  exports :config_c

  def run
    puts "Fetching config C..."
    sleep(0.08)
    @config_c = {debug: false, verbose: true}
  end
end

class DownloadAssetA < Taski::Task
  exports :asset_a

  def run
    puts "Downloading asset A (images)..."
    sleep(0.3)
    @asset_a = "images.tar.gz"
  end
end

class DownloadAssetB < Taski::Task
  exports :asset_b

  def run
    puts "Downloading asset B (fonts)..."
    sleep(0.25)
    @asset_b = "fonts.tar.gz"
  end
end

class DownloadAssetC < Taski::Task
  exports :asset_c

  def run
    puts "Downloading asset C (icons)..."
    sleep(0.2)
    @asset_c = "icons.tar.gz"
  end
end

class DownloadAssetD < Taski::Task
  exports :asset_d

  def run
    puts "Downloading asset D (templates)..."
    sleep(0.35)
    @asset_d = "templates.tar.gz"
  end
end

class FetchSchemaV1 < Taski::Task
  exports :schema_v1

  def run
    puts "Fetching schema v1..."
    sleep(0.12)
    @schema_v1 = {version: 1, tables: 10}
  end
end

class FetchSchemaV2 < Taski::Task
  exports :schema_v2

  def run
    puts "Fetching schema v2..."
    sleep(0.18)
    @schema_v2 = {version: 2, tables: 15}
  end
end

class FetchSchemaV3 < Taski::Task
  exports :schema_v3

  def run
    puts "Fetching schema v3..."
    sleep(0.14)
    @schema_v3 = {version: 3, tables: 20}
  end
end

class LoadEnvDev < Taski::Task
  exports :env_dev

  def run
    puts "Loading dev environment..."
    sleep(0.05)
    @env_dev = "development"
  end
end

class LoadEnvStaging < Taski::Task
  exports :env_staging

  def run
    puts "Loading staging environment..."
    sleep(0.06)
    @env_staging = "staging"
  end
end

class LoadEnvProd < Taski::Task
  exports :env_prod

  def run
    puts "Loading production environment..."
    sleep(0.07)
    @env_prod = "production"
  end
end

class CheckDependencyA < Taski::Task
  exports :dep_a_ok

  def run
    puts "Checking dependency A (Ruby)..."
    sleep(0.1)
    @dep_a_ok = true
  end
end

class CheckDependencyB < Taski::Task
  exports :dep_b_ok

  def run
    puts "Checking dependency B (Node)..."
    sleep(0.12)
    @dep_b_ok = true
  end
end

class CheckDependencyC < Taski::Task
  exports :dep_c_ok

  def run
    puts "Checking dependency C (Python)..."
    sleep(0.08)
    @dep_c_ok = true
  end
end

class CheckDependencyD < Taski::Task
  exports :dep_d_ok

  def run
    puts "Checking dependency D (Go)..."
    sleep(0.09)
    @dep_d_ok = true
  end
end

class CheckDependencyE < Taski::Task
  exports :dep_e_ok

  def run
    puts "Checking dependency E (Rust)..."
    sleep(0.11)
    @dep_e_ok = true
  end
end

# Level 3: Aggregation tasks
class MergeConfigs < Taski::Task
  exports :merged_config

  def run
    config_a = FetchConfigA.config_a
    config_b = FetchConfigB.config_b
    config_c = FetchConfigC.config_c
    puts "Merging configs..."
    sleep(0.2)
    @merged_config = config_a.merge(config_b).merge(config_c)
  end
end

class BundleAssets < Taski::Task
  exports :bundled_assets

  def run
    asset_a = DownloadAssetA.asset_a
    asset_b = DownloadAssetB.asset_b
    asset_c = DownloadAssetC.asset_c
    asset_d = DownloadAssetD.asset_d
    puts "Bundling assets: #{asset_a}, #{asset_b}, #{asset_c}, #{asset_d}..."
    sleep(0.4)
    @bundled_assets = [asset_a, asset_b, asset_c, asset_d]
  end
end

class MigrateDatabase < Taski::Task
  exports :migration_result

  def run
    schema_v1 = FetchSchemaV1.schema_v1
    FetchSchemaV2.schema_v2
    schema_v3 = FetchSchemaV3.schema_v3
    puts "Running migrations v1->v2->v3..."
    sleep(0.5)
    @migration_result = {from: schema_v1[:version], to: schema_v3[:version]}
  end
end

class PrepareEnvironments < Taski::Task
  exports :environments

  def run
    dev = LoadEnvDev.env_dev
    staging = LoadEnvStaging.env_staging
    prod = LoadEnvProd.env_prod
    puts "Preparing environments: #{dev}, #{staging}, #{prod}..."
    sleep(0.15)
    @environments = [dev, staging, prod]
  end
end

class ValidateDependencies < Taski::Task
  exports :all_deps_ok

  def run
    deps = [
      CheckDependencyA.dep_a_ok,
      CheckDependencyB.dep_b_ok,
      CheckDependencyC.dep_c_ok,
      CheckDependencyD.dep_d_ok,
      CheckDependencyE.dep_e_ok
    ]
    puts "Validating all dependencies..."
    sleep(0.1)
    @all_deps_ok = deps.all?
  end
end

# Additional leaf tasks for more breadth
class GenerateCacheKeyA < Taski::Task
  exports :cache_key_a

  def run
    puts "Generating cache key A..."
    sleep(0.05)
    @cache_key_a = "cache_a_#{rand(1000)}"
  end
end

class GenerateCacheKeyB < Taski::Task
  exports :cache_key_b

  def run
    puts "Generating cache key B..."
    sleep(0.06)
    @cache_key_b = "cache_b_#{rand(1000)}"
  end
end

class GenerateCacheKeyC < Taski::Task
  exports :cache_key_c

  def run
    puts "Generating cache key C..."
    sleep(0.04)
    @cache_key_c = "cache_c_#{rand(1000)}"
  end
end

class WarmCacheA < Taski::Task
  exports :cache_a_warmed

  def run
    key = GenerateCacheKeyA.cache_key_a
    puts "Warming cache A with key: #{key}..."
    sleep(0.2)
    @cache_a_warmed = true
  end
end

class WarmCacheB < Taski::Task
  exports :cache_b_warmed

  def run
    key = GenerateCacheKeyB.cache_key_b
    puts "Warming cache B with key: #{key}..."
    sleep(0.15)
    @cache_b_warmed = true
  end
end

class WarmCacheC < Taski::Task
  exports :cache_c_warmed

  def run
    key = GenerateCacheKeyC.cache_key_c
    puts "Warming cache C with key: #{key}..."
    sleep(0.18)
    @cache_c_warmed = true
  end
end

class PrepareCaches < Taski::Task
  exports :caches_ready

  def run
    WarmCacheA.cache_a_warmed
    WarmCacheB.cache_b_warmed
    WarmCacheC.cache_c_warmed
    puts "All caches prepared..."
    sleep(0.1)
    @caches_ready = true
  end
end

# More leaf tasks
class FetchApiKeyA < Taski::Task
  exports :api_key_a

  def run
    puts "Fetching API key A..."
    sleep(0.08)
    @api_key_a = "key_a_secret"
  end
end

class FetchApiKeyB < Taski::Task
  exports :api_key_b

  def run
    puts "Fetching API key B..."
    sleep(0.09)
    @api_key_b = "key_b_secret"
  end
end

class FetchApiKeyC < Taski::Task
  exports :api_key_c

  def run
    puts "Fetching API key C..."
    sleep(0.07)
    @api_key_c = "key_c_secret"
  end
end

class ValidateApiKeys < Taski::Task
  exports :api_keys_valid

  def run
    FetchApiKeyA.api_key_a
    FetchApiKeyB.api_key_b
    FetchApiKeyC.api_key_c
    puts "Validating API keys..."
    sleep(0.15)
    @api_keys_valid = true
  end
end

# Level 2: Integration tasks
class SetupInfrastructure < Taski::Task
  exports :infra_ready

  def run
    MergeConfigs.merged_config
    PrepareEnvironments.environments
    ValidateDependencies.all_deps_ok
    puts "Setting up infrastructure..."
    sleep(0.3)
    @infra_ready = true
  end
end

class PrepareStaticAssets < Taski::Task
  exports :static_assets_ready

  def run
    BundleAssets.bundled_assets
    puts "Preparing static assets..."
    sleep(0.25)
    @static_assets_ready = true
  end
end

class SetupDatabase < Taski::Task
  exports :database_ready

  def run
    MigrateDatabase.migration_result
    puts "Setting up database..."
    sleep(0.35)
    @database_ready = true
  end
end

class InitializeCaches < Taski::Task
  exports :caches_initialized

  def run
    PrepareCaches.caches_ready
    puts "Initializing caches..."
    sleep(0.2)
    @caches_initialized = true
  end
end

class SetupAuthentication < Taski::Task
  exports :auth_ready

  def run
    ValidateApiKeys.api_keys_valid
    puts "Setting up authentication..."
    sleep(0.25)
    @auth_ready = true
  end
end

# Level 1: High-level integration
class PrepareBackend < Taski::Task
  exports :backend_ready

  def run
    SetupInfrastructure.infra_ready
    SetupDatabase.database_ready
    SetupAuthentication.auth_ready
    puts "Preparing backend services..."
    sleep(0.4)
    @backend_ready = true
  end
end

class PrepareFrontend < Taski::Task
  exports :frontend_ready

  def run
    PrepareStaticAssets.static_assets_ready
    InitializeCaches.caches_initialized
    puts "Preparing frontend..."
    sleep(0.3)
    @frontend_ready = true
  end
end

class RunHealthChecks < Taski::Task
  exports :health_ok

  def run
    PrepareBackend.backend_ready
    PrepareFrontend.frontend_ready
    puts "Running health checks..."
    sleep(0.2)
    @health_ok = true
  end
end

# Root task
class DeployApplication < Taski::Task
  exports :deploy_result

  def run
    RunHealthChecks.health_ok
    puts "Deploying application..."
    sleep(0.5)
    @deploy_result = "Deployed successfully at #{Time.now}"
  end
end

# Optional: Uncomment to test failure handling
# class FailingTask < Taski::Task
#   exports :will_fail
#
#   def run
#     puts "This task will fail..."
#     sleep(0.1)
#     raise "Intentional failure for testing"
#   end
# end

if __FILE__ == $0
  puts "Large Tree Demo - 52 tasks with nested dependencies"
  puts "=" * 50
  puts ""

  begin
    result = DeployApplication.deploy_result
    puts "\n\nFinal result: #{result}"
  rescue => e
    puts "\n\nExecution failed: #{e.message}"
  end
end
