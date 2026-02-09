# frozen_string_literal: true

require_relative "../../lib/taski"

module RunAndCleanFixtures
  # Thread-safe order tracking for run phase
  module RunOrder
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

  # Thread-safe order tracking for clean phase
  module CleanOrder
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

  class BaseTask < Taski::Task
    exports :base_value

    def run
      @base_value = "base"
      RunOrder.add(:base)
    end

    def clean
      CleanOrder.add(:base)
    end
  end

  class ChildTask < Taski::Task
    exports :child_value

    def run
      base = BaseTask.base_value
      RunOrder.add(:child)
      @child_value = base + "_child"
    end

    def clean
      CleanOrder.add(:child)
    end
  end

  # Thread-safe tracker for clean_on_failure tests
  module CleanOnFailureTracker
    @run_executed = false
    @clean_executed = false
    @mutex = Mutex.new

    class << self
      def record_run
        @mutex.synchronize { @run_executed = true }
      end

      def record_clean
        @mutex.synchronize { @clean_executed = true }
      end

      def run_executed?
        @mutex.synchronize { @run_executed }
      end

      def clean_executed?
        @mutex.synchronize { @clean_executed }
      end

      def clear
        @mutex.synchronize do
          @run_executed = false
          @clean_executed = false
        end
      end
    end
  end

  # Task that fails in run — used for clean_on_failure tests
  class FailingCleanableTask < Taski::Task
    exports :value

    def run
      CleanOnFailureTracker.record_run
      raise StandardError, "Run failed"
    end

    def clean
      CleanOnFailureTracker.record_clean
    end
  end

  # Task that succeeds in run — used for success + clean verification
  class SucceedingCleanableTask < Taski::Task
    exports :value

    def run
      @value = "ok"
    end

    def clean
      CleanOnFailureTracker.record_clean
    end
  end

  # Thread-safe order tracking for block execution tests
  module BlockOrder
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

  # Task with computed result for run_and_clean return value test
  class ComputedResultTask < Taski::Task
    exports :computed

    def run
      @computed = 42 * 2
    end

    def clean
      # Cleanup logic
    end
  end

  # Task for basic run_and_clean execution order test
  class TrackedRunCleanTask < Taski::Task
    exports :value

    def run
      BlockOrder.add(:run)
      @value = "test_value"
    end

    def clean
      BlockOrder.add(:clean)
    end
  end

  # Task for run_and_clean with block test
  class TrackedBlockTask < Taski::Task
    exports :value

    def run
      BlockOrder.add(:run)
      @value = "test_value"
    end

    def clean
      BlockOrder.add(:clean)
    end
  end

  # Task for block access to exported values test
  class ExportedDataTask < Taski::Task
    exports :value

    def run
      @value = "exported_data"
    end

    def clean
    end
  end

  # Task for stdout capture test
  class StdoutTestTask < Taski::Task
    exports :value

    def run
      @value = "test"
    end

    def clean
    end
  end

  # Thread-safe tracker for block error + clean test
  module BlockErrorTracker
    @clean_executed = false
    @mutex = Mutex.new

    class << self
      def record_clean
        @mutex.synchronize { @clean_executed = true }
      end

      def clean_executed?
        @mutex.synchronize { @clean_executed }
      end

      def clear
        @mutex.synchronize { @clean_executed = false }
      end
    end
  end

  # Task for block error still cleans test
  class CleanOnBlockErrorTask < Taski::Task
    exports :value

    def run
      @value = "test"
    end

    def clean
      BlockErrorTracker.record_clean
    end
  end
end
