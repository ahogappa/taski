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

module DeepDependency
  class TaskD < Taski::Task
    exports :task_d_value

    def run
      @task_d_value = "TaskD: #{ParallelTaskC.task_c_value}"
    end
  end

  class TaskE < Taski::Task
    exports :task_e_value

    def run
      @task_e_value = "TaskE: #{TaskD.task_d_value}"
    end
  end

  class TaskF < Taski::Task
    exports :task_f_value

    def run
      @task_f_value = "TaskF: #{::ParallelTaskA.task_a_value}"
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

# Test fixture for namespaced helper method with relative constant reference
# When Helper.run calls collect_data which references RelativeTask,
# static analysis should resolve RelativeTask within the Helper namespace
module NamespacedHelper
  class DependencyTask < Taski::Task
    exports :data

    def run
      @data = "dependency_data"
    end
  end

  class HelperTask < Taski::Task
    exports :result

    def run
      @result = collect_dependencies
    end

    private

    def collect_dependencies
      # Relative constant reference - should resolve to NamespacedHelper::DependencyTask
      DependencyTask.data + "_processed"
    end
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

class SystemCallStderrTask < Taski::Task
  exports :result

  def run
    # Write to stderr - should be captured via err: [:child, :out]
    @result = system("ruby -e 'STDERR.puts \"stderr_message\"'")
  end
end
