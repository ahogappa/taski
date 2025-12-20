# frozen_string_literal: true

require "taski"

# Test fixtures for static dependency analysis

class FixtureTaskA < Taski::Task
  exports :value_a

  def run
    @value_a = "A"
  end
end

class FixtureTaskB < Taski::Task
  exports :value_b

  def run
    @value_b = "B depends on #{FixtureTaskA.value_a}"
  end
end

module FixtureNamespace
  class TaskC < Taski::Task
    exports :value_c

    def run
      @value_c = "C depends on #{FixtureTaskA.value_a}"
    end
  end

  class TaskD < Taski::Task
    exports :value_d

    def run
      @value_d = "D depends on #{TaskC.value_c}"
    end
  end
end

# Complex test fixtures for parallel execution testing

class ParallelTaskA < Taski::Task
  exports :task_a_value

  def run
    @task_a_value = "TaskA value #{rand(10000)}"
  end
end

class ParallelTaskB < Taski::Task
  exports :task_b_value

  def run
    sleep(0.5) # Simulate slow task
    @task_b_value = "TaskB value"
  end
end

class ParallelTaskC < Taski::Task
  exports :task_c_value

  def run
    # Depends on both TaskA and TaskB
    @task_c_value = "TaskC: #{ParallelTaskA.task_a_value} and #{ParallelTaskB.task_b_value}"
  end
end

class ParallelSectionImpl1 < Taski::Task
  exports :section_value

  def run
    @section_value = "Section Implementation 1"
  end
end

class ParallelSectionImpl2 < Taski::Task
  exports :section_value

  def run
    sleep(0.3) # Simulate slow implementation
    @section_value = "Section Implementation 2"
  end
end

class ParallelSection < Taski::Section
  interfaces :section_value

  def impl
    ParallelSectionImpl2
  end
end

module DeepDependency
  class TaskD < Taski::Task
    exports :task_d_value

    def run
      @task_d_value = "TaskD: #{ParallelTaskC.task_c_value} and #{ParallelSection.section_value}"
    end
  end

  class TaskE < Taski::Task
    exports :task_e_value

    def run
      @task_e_value = "TaskE: #{TaskD.task_d_value} and #{ParallelSection.section_value}"
    end
  end

  class TaskF < Taski::Task
    exports :task_f_value

    def run
      @task_f_value = "TaskF: #{::ParallelTaskA.task_a_value} and #{ParallelSection.section_value}"
    end
  end

  module Nested
    class TaskG < Taski::Task
      exports :task_g_value

      def run
        @task_g_value = "TaskG: #{DeepDependency::TaskE.task_e_value} and #{DeepDependency::TaskF.task_f_value}"
      end
    end

    class TaskH < Taski::Task
      exports :task_h_value

      def run
        @task_h_value = "TaskH: #{TaskG.task_g_value}"
      end
    end
  end
end

# Test fixtures for execution order testing

class SequentialTaskA < Taski::Task
  exports :value

  def run
    @value = "A"
  end
end

class SequentialTaskB < Taski::Task
  exports :value

  def run
    @value = "B->#{SequentialTaskA.value}"
  end
end

class SequentialTaskC < Taski::Task
  exports :value

  def run
    @value = "C->#{SequentialTaskB.value}"
  end
end

class SequentialTaskD < Taski::Task
  exports :value

  def run
    @value = "D->#{SequentialTaskC.value}"
  end
end

# Test fixtures for parallel chain execution
# Module to track start times for verifying parallel execution
module ParallelChainStartTimes
  @start_times = {}
  @mutex = Mutex.new

  class << self
    def record(task_name)
      @mutex.synchronize do
        @start_times[task_name] = Time.now
      end
    end

    def get(task_name)
      @mutex.synchronize do
        @start_times[task_name]
      end
    end

    def reset
      @mutex.synchronize do
        @start_times = {}
      end
    end
  end
end

class ParallelChain1A < Taski::Task
  exports :value

  def run
    ParallelChainStartTimes.record(:chain1a)
    sleep(0.1)
    @value = "Chain1-A"
  end
end

class ParallelChain1B < Taski::Task
  exports :value

  def run
    sleep(0.1)
    @value = "Chain1-B->#{ParallelChain1A.value}"
  end
end

class ParallelChain2C < Taski::Task
  exports :value

  def run
    ParallelChainStartTimes.record(:chain2c)
    sleep(0.1)
    @value = "Chain2-C"
  end
end

class ParallelChain2D < Taski::Task
  exports :value

  def run
    sleep(0.1)
    @value = "Chain2-D->#{ParallelChain2C.value}"
  end
end

class ParallelChainFinal < Taski::Task
  exports :value

  def run
    @value = "Final: #{ParallelChain1B.value} and #{ParallelChain2D.value}"
  end
end

# Test fixtures for clean functionality

class CleanTaskA < Taski::Task
  exports :value

  def run
    @value = "A"
  end

  def clean
    @value = nil
    "cleaned_A"
  end
end

class CleanTaskB < Taski::Task
  exports :value

  def run
    @value = "B->#{CleanTaskA.value}"
  end

  def clean
    @value = nil
    "cleaned_B"
  end
end

class CleanTaskC < Taski::Task
  exports :value

  def run
    @value = "C->#{CleanTaskB.value}"
  end

  def clean
    @value = nil
    "cleaned_C"
  end
end

class CleanTaskD < Taski::Task
  exports :value

  def run
    @value = "D->#{CleanTaskC.value}"
  end

  def clean
    @value = nil
    "cleaned_D"
  end
end

# Test fixtures for Section with nested implementations
# Nested classes automatically inherit interfaces from parent Section

class NestedSection < Taski::Section
  interfaces :host, :port

  # No exports needed - automatically inherited from interfaces
  class LocalDB < Taski::Task
    def run
      @host = "localhost"
      @port = 5432
    end
  end

  class ProductionDB < Taski::Task
    def run
      @host = "prod.example.com"
      @port = 5432
    end
  end

  def impl
    LocalDB
  end
end

# Section that uses external implementation (traditional pattern)
class ExternalImplSection < Taski::Section
  interfaces :value

  def impl
    ExternalImpl
  end
end

class ExternalImpl < Taski::Task
  exports :value

  def run
    @value = "external implementation"
  end
end

# Test fixtures for nested Section (Section inside Section)
# OuterSection's impl returns InnerSection (which is also a Section)

class InnerSection < Taski::Section
  interfaces :db_url

  class InnerImpl < Taski::Task
    exports :db_url

    def run
      @db_url = "postgres://localhost:5432/mydb"
    end
  end

  def impl
    InnerImpl
  end
end

class OuterSection < Taski::Section
  interfaces :db_url

  def impl
    InnerSection
  end
end

# Test fixtures for lazy dependency resolution in Section
# When impl returns OptionB, OptionA's dependencies should NOT be executed
# Test fixtures for Section.impl depending on other tasks
# Example: def impl = TaskA.value ? TaskB : TaskC
module ImplDependsOnTaskTest
  @executed_tasks = []
  @mutex = Mutex.new

  class << self
    def record(task_name)
      @mutex.synchronize do
        @executed_tasks << task_name
      end
    end

    def executed_tasks
      @mutex.synchronize { @executed_tasks.dup }
    end

    def reset
      @mutex.synchronize { @executed_tasks = [] }
    end
  end

  # Task that determines which implementation to use
  class ConditionTask < Taski::Task
    exports :use_fast_mode

    def run
      ImplDependsOnTaskTest.record(:condition_task)
      # Use context to control condition for testing
      @use_fast_mode = Taski.context[:fast_mode] || false
    end
  end

  # Fast implementation
  class FastImpl < Taski::Task
    exports :result

    def run
      ImplDependsOnTaskTest.record(:fast_impl)
      @result = "fast result"
    end
  end

  # Slow implementation with its own dependency
  class SlowDependency < Taski::Task
    exports :data

    def run
      ImplDependsOnTaskTest.record(:slow_dependency)
      @data = "slow data"
    end
  end

  class SlowImpl < Taski::Task
    exports :result

    def run
      ImplDependsOnTaskTest.record(:slow_impl)
      @result = "slow result with #{SlowDependency.data}"
    end
  end

  # Section where impl depends on ConditionTask's value
  class ConditionalSection < Taski::Section
    interfaces :result

    def impl
      ImplDependsOnTaskTest.record(:impl_called)
      # impl method depends on another task's value
      # This will block until ConditionTask completes
      if ConditionTask.use_fast_mode
        FastImpl
      else
        SlowImpl
      end
    end
  end

  # Task that depends on the Section
  class FinalTask < Taski::Task
    exports :output

    def run
      ImplDependsOnTaskTest.record(:final_task)
      @output = "final: #{ConditionalSection.result}"
    end
  end
end

# Test fixtures for static analysis following method calls
# When run method calls private methods, dependencies in those methods should be detected

class MethodCallBaseTask < Taski::Task
  exports :base_value

  def run
    @base_value = "base"
  end
end

class MethodCallFollowTask < Taski::Task
  exports :result

  def run
    @result = process_data
  end

  private

  def process_data
    # This dependency should be detected by static analysis
    MethodCallBaseTask.base_value + "_processed"
  end
end

# Test fixture for nested method calls (run -> helper1 -> helper2)
class NestedMethodCallTask < Taski::Task
  exports :result

  def run
    @result = step1
  end

  private

  def step1
    step2 + "_step1"
  end

  def step2
    # Nested dependency - two levels deep from run
    MethodCallBaseTask.base_value + "_step2"
  end
end

# Test fixture for multiple methods with dependencies
class MultiMethodTask < Taski::Task
  exports :result

  def run
    @result = "#{get_base}_#{get_other}"
  end

  private

  def get_base
    MethodCallBaseTask.base_value
  end

  def get_other
    MethodCallFollowTask.result
  end
end

# Test fixture for Section with method calls in impl
class MethodCallSectionImpl < Taski::Task
  exports :section_value

  def run
    @section_value = "section_impl"
  end
end

class MethodCallSection < Taski::Section
  interfaces :section_value

  def impl
    select_impl
  end

  private

  def select_impl
    MethodCallSectionImpl
  end
end

# Test fixtures for subprocess output capture (system() and backticks)

class SystemCallTask < Taski::Task
  exports :result

  def run
    @result = system("echo", "system_output")
  end
end

class SystemCallShellModeTask < Taski::Task
  exports :result

  def run
    @result = system("echo shell_mode_output")
  end
end

class SystemCallFailingTask < Taski::Task
  exports :result

  def run
    @result = system("exit 1")
  end
end

module LazyDependencyTest
  # Track which tasks have been executed with timestamps
  @executed_tasks = []
  @impl_call_order = nil
  @mutex = Mutex.new

  class << self
    attr_accessor :impl_call_order

    def record(task_name)
      @mutex.synchronize do
        @executed_tasks << {name: task_name, time: Time.now}
      end
    end

    def executed_tasks
      @mutex.synchronize do
        @executed_tasks.map { |entry| entry[:name] }
      end
    end

    def executed_before_impl?(task_name)
      @mutex.synchronize do
        return false unless @impl_call_order
        task_entry = @executed_tasks.find { |entry| entry[:name] == task_name }
        return false unless task_entry
        task_entry[:time] < @impl_call_order
      end
    end

    def reset
      @mutex.synchronize do
        @executed_tasks = []
        @impl_call_order = nil
      end
    end
  end

  # Expensive task that should NOT be executed when OptionA is not selected
  class ExpensiveTask < Taski::Task
    exports :value

    def run
      LazyDependencyTest.record(:expensive_task)
      @value = "expensive"
    end
  end

  # Cheap task that OptionB depends on
  class CheapTask < Taski::Task
    exports :value

    def run
      LazyDependencyTest.record(:cheap_task)
      @value = "cheap"
    end
  end

  # Section with two options, each with different dependencies
  # Bug: When impl has conditional, all candidates' dependencies are executed
  class MySection < Taski::Section
    interfaces :value

    # OptionA depends on ExpensiveTask
    class OptionA < Taski::Task
      exports :value

      def run
        LazyDependencyTest.record(:option_a)
        @value = "A with #{ExpensiveTask.value}"
      end
    end

    # OptionB depends on CheapTask
    class OptionB < Taski::Task
      exports :value

      def run
        LazyDependencyTest.record(:option_b)
        @value = "B with #{CheapTask.value}"
      end
    end

    def impl
      LazyDependencyTest.impl_call_order = Time.now
      # Conditional selection - both OptionA and OptionB are referenced in impl
      # Only the selected option's dependencies should be executed
      if Taski.context[:use_option_a]
        OptionA
      else
        OptionB
      end
    end
  end
end
