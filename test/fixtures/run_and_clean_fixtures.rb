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
end
