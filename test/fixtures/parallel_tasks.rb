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
