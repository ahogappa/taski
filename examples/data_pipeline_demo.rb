#!/usr/bin/env ruby
# frozen_string_literal: true

# Taski Data Pipeline Example
#
# This example demonstrates a realistic data processing pipeline:
# - Section API for switching data sources (production vs test)
# - Multiple data sources fetched in parallel
# - Data transformation and aggregation
#
# Run: ruby examples/data_pipeline_demo.rb
# Disable progress: TASKI_PROGRESS_DISABLE=1 ruby examples/data_pipeline_demo.rb

require_relative "../lib/taski"

# Section: Data source abstraction
# Switch between production API and test fixtures
class DataSourceSection < Taski::Section
  interfaces :users, :sales, :activities

  def impl
    (ENV["USE_TEST_DATA"] == "true") ? TestData : ProductionData
  end

  # Production: Fetch from APIs (simulated with delays)
  class ProductionData < Taski::Task
    def run
      puts "  [ProductionData] Fetching from APIs..."
      sleep(0.3)

      @users = [
        {id: 1, name: "Alice", department: "Engineering"},
        {id: 2, name: "Bob", department: "Sales"},
        {id: 3, name: "Charlie", department: "Engineering"},
        {id: 4, name: "Diana", department: "Marketing"}
      ]

      @sales = [
        {user_id: 2, amount: 1000, date: "2024-01"},
        {user_id: 2, amount: 1500, date: "2024-02"},
        {user_id: 4, amount: 800, date: "2024-01"}
      ]

      @activities = [
        {user_id: 1, action: :commit, count: 45},
        {user_id: 3, action: :commit, count: 32},
        {user_id: 1, action: :review, count: 12},
        {user_id: 3, action: :review, count: 8}
      ]

      puts "  [ProductionData] Loaded #{@users.size} users, #{@sales.size} sales, #{@activities.size} activities"
    end
  end

  # Test: Minimal fixture data (no delays)
  class TestData < Taski::Task
    def run
      puts "  [TestData] Loading test fixtures..."

      @users = [
        {id: 1, name: "Test User", department: "Test Dept"}
      ]

      @sales = [
        {user_id: 1, amount: 100, date: "2024-01"}
      ]

      @activities = [
        {user_id: 1, action: :commit, count: 10}
      ]

      puts "  [TestData] Loaded minimal test data"
    end
  end
end

# Section: Report format selection
class ReportFormatSection < Taski::Section
  interfaces :format_report

  def impl
    (ENV["REPORT_FORMAT"] == "json") ? JsonFormat : TextFormat
  end

  class TextFormat < Taski::Task
    def run
      @format_report = ->(report) {
        report.map do |dept, stats|
          "#{dept}: #{stats[:user_count]} users, $#{stats[:total_sales]} sales"
        end.join("\n")
      }
    end
  end

  class JsonFormat < Taski::Task
    def run
      require "json"
      @format_report = ->(report) { JSON.pretty_generate(report) }
    end
  end
end

# Transform: Enrich users with sales data
class EnrichWithSales < Taski::Task
  exports :users_with_sales

  def run
    users = DataSourceSection.users
    sales = DataSourceSection.sales

    sales_by_user = sales.group_by { |s| s[:user_id] }
      .transform_values { |records| records.sum { |r| r[:amount] } }

    @users_with_sales = users.map do |user|
      user.merge(total_sales: sales_by_user[user[:id]] || 0)
    end

    puts "  [EnrichWithSales] Enriched #{@users_with_sales.size} users"
  end
end

# Transform: Enrich users with activity data
class EnrichWithActivities < Taski::Task
  exports :users_with_activities

  def run
    users = DataSourceSection.users
    activities = DataSourceSection.activities

    activities_by_user = activities.group_by { |a| a[:user_id] }
      .transform_values do |records|
      records.to_h { |r| [r[:action], r[:count]] }
    end

    @users_with_activities = users.map do |user|
      user.merge(activities: activities_by_user[user[:id]] || {})
    end

    puts "  [EnrichWithActivities] Enriched #{@users_with_activities.size} users"
  end
end

# Aggregate: Combine enrichments into profiles
class BuildProfiles < Taski::Task
  exports :profiles

  def run
    users_sales = EnrichWithSales.users_with_sales
    users_activities = EnrichWithActivities.users_with_activities

    activities_map = users_activities.to_h { |u| [u[:id], u[:activities]] }

    @profiles = users_sales.map do |user|
      user.merge(activities: activities_map[user[:id]] || {})
    end

    puts "  [BuildProfiles] Built #{@profiles.size} profiles"
  end
end

# Output: Generate department report
class GenerateReport < Taski::Task
  exports :report, :formatted_output

  def run
    profiles = BuildProfiles.profiles
    formatter = ReportFormatSection.format_report

    by_department = profiles.group_by { |p| p[:department] }

    @report = by_department.transform_values do |dept_users|
      {
        user_count: dept_users.size,
        total_sales: dept_users.sum { |u| u[:total_sales] },
        total_commits: dept_users.sum { |u| u[:activities][:commit] || 0 },
        total_reviews: dept_users.sum { |u| u[:activities][:review] || 0 }
      }
    end

    @formatted_output = formatter.call(@report)
    puts "  [GenerateReport] Generated report for #{@report.size} departments"
  end
end

# Demo execution
puts "Taski Data Pipeline Demo"
puts "=" * 50

puts "\n1. Dependency Tree"
puts "-" * 50
puts GenerateReport.tree

puts "\n2. Production Data (default)"
puts "-" * 50
ENV["USE_TEST_DATA"] = "false"
ENV["REPORT_FORMAT"] = "text"

start_time = Time.now
GenerateReport.run
elapsed = Time.now - start_time

puts "\nReport (text format):"
puts GenerateReport.formatted_output
puts "\nCompleted in #{elapsed.round(3)}s"

puts "\n" + "=" * 50
puts "\n3. Test Data with JSON Format"
puts "-" * 50
ENV["USE_TEST_DATA"] = "true"
ENV["REPORT_FORMAT"] = "json"

# Reset all tasks for fresh execution
[DataSourceSection, ReportFormatSection, EnrichWithSales,
  EnrichWithActivities, BuildProfiles, GenerateReport].each(&:reset!)

start_time = Time.now
GenerateReport.run
elapsed = Time.now - start_time

puts "\nReport (JSON format):"
puts GenerateReport.formatted_output
puts "\nCompleted in #{elapsed.round(3)}s"

puts "\n" + "=" * 50
puts "Pipeline demonstration complete!"
puts "\nKey concepts demonstrated:"
puts "  - DataSourceSection: Switch between production/test data"
puts "  - ReportFormatSection: Switch output format (text/JSON)"
puts "  - Parallel execution of independent transforms"
puts "\nTo disable progress display:"
puts "  TASKI_PROGRESS_DISABLE=1 ruby examples/data_pipeline_demo.rb"
