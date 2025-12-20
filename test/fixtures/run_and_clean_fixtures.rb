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
      RunOrder.add(:base)
      @base_value = "base"
    end

    def clean
      CleanOrder.add(:base)
    end
  end

  class ChildTask < Taski::Task
    exports :child_value

    def run
      RunOrder.add(:child)
      @child_value = BaseTask.base_value + "_child"
    end

    def clean
      CleanOrder.add(:child)
    end
  end
end
