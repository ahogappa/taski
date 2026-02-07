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
end
