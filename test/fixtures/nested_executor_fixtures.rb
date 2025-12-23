# frozen_string_literal: true

require_relative "../../lib/taski"

# Fixtures to test nested executor behavior when dependencies are already completed
# in the parent executor. This tests the scenario where a Section triggers a nested
# executor to run its implementation, and that implementation depends on tasks that
# have already been executed by the parent executor.
module NestedExecutorFixtures
  # Synchronization primitive to control task execution timing
  class Barrier
    def initialize
      @mutex = Mutex.new
      @cond = ConditionVariable.new
      @released = false
    end

    def wait
      @mutex.synchronize do
        @cond.wait(@mutex) until @released
      end
    end

    def release
      @mutex.synchronize do
        @released = true
        @cond.broadcast
      end
    end

    def reset
      @mutex.synchronize do
        @released = false
      end
    end
  end

  # Thread-safe order tracking
  module ExecutionOrder
    @order = []
    @mutex = Mutex.new

    class << self
      def add(symbol)
        @mutex.synchronize { @order << symbol }
      end

      def order
        @mutex.synchronize { @order.dup }
      end

      def clear
        @mutex.synchronize { @order.clear }
      end
    end
  end

  def self.reset_all
    ExecutionOrder.clear
    slow_task_barrier.reset
    Taski::Task.reset!
  end

  # A shared dependency that will be executed by the parent executor first
  # and then should be recognized as completed when the nested executor runs
  class SharedDependency < Taski::Task
    exports :data

    def run
      ExecutionOrder.add(:shared_dependency)
      @data = "shared data"
    end
  end

  # Implementation task that depends on SharedDependency
  # This will be run by a nested executor triggered by TestSection
  class SectionImpl < Taski::Task
    exports :result

    def run
      ExecutionOrder.add(:section_impl)
      # Access SharedDependency which should already be completed
      @result = "impl using: #{SharedDependency.data}"
    end
  end

  # Section that selects SectionImpl at runtime
  # When this runs, it triggers a nested executor to run SectionImpl
  class TestSection < Taski::Section
    interfaces :result

    def impl
      SectionImpl
    end

    def run
      ExecutionOrder.add(:test_section)
      super
    end
  end

  # Parent task that depends on both SharedDependency and TestSection
  # This ensures SharedDependency is completed before TestSection runs
  class ParentTask < Taski::Task
    exports :output

    def run
      ExecutionOrder.add(:parent_task)
      # Access both - SharedDependency should complete first due to parallel scheduling
      shared = SharedDependency.data
      section_result = TestSection.result
      @output = "#{shared} + #{section_result}"
    end
  end

  # ========================================
  # Fixtures for testing "running dependency" scenario
  # ========================================
  # This tests the case where a nested executor tries to enqueue a dependency
  # that is currently RUNNING (not yet completed) in a parallel worker thread.
  # The nested executor must wait for the running dependency to complete.

  # Barrier to synchronize task execution for deterministic testing
  @slow_task_barrier = Barrier.new

  class << self
    attr_reader :slow_task_barrier
  end

  # A Section that takes time to complete (simulates CargoPath in real scenario)
  # Uses a barrier to ensure it's still running when the nested executor checks
  class SlowSection < Taski::Section
    interfaces :path

    class SlowImpl < Taski::Task
      exports :path

      def run
        ExecutionOrder.add(:slow_impl_start)
        # Wait at barrier - this keeps the task in "running" state
        # until the test releases it
        NestedExecutorFixtures.slow_task_barrier.wait
        ExecutionOrder.add(:slow_impl_end)
        @path = "/slow/path"
      end
    end

    def impl
      SlowImpl
    end
  end

  # Implementation task that depends on SlowSection
  # When this runs in a nested executor, SlowSection may still be running
  class DependsOnSlowSection < Taski::Task
    exports :result

    def run
      ExecutionOrder.add(:depends_on_slow_start)
      # This access will trigger the nested executor to wait for SlowSection
      path = SlowSection.path
      ExecutionOrder.add(:depends_on_slow_end)
      @result = "using: #{path}"
    end
  end

  # Section that selects DependsOnSlowSection as implementation
  class FastSection < Taski::Section
    interfaces :result

    def impl
      DependsOnSlowSection
    end

    def run
      ExecutionOrder.add(:fast_section)
      super
    end
  end

  # Root task that triggers parallel execution of SlowSection and FastSection
  # Both sections run in parallel, creating a race condition
  class RaceConditionTask < Taski::Task
    exports :output

    def run
      ExecutionOrder.add(:race_task)
      # Access both - they will run in parallel
      # FastSection's impl (DependsOnSlowSection) depends on SlowSection
      # which may still be running when the nested executor tries to enqueue it
      slow_result = SlowSection.path
      fast_result = FastSection.result
      @output = "#{slow_result} + #{fast_result}"
    end
  end
end
