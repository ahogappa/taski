# frozen_string_literal: true

require_relative "../../lib/taski"

module SectionCleanFixtures
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

  def self.reset_all
    RunOrder.clear
    CleanOrder.clear
    Taski::Task.reset!
  end

  # Database implementation task
  class LocalDBImpl < Taski::Task
    exports :connection_string

    def run
      RunOrder.add(:local_db_impl)
      @connection_string = "localhost:5432"
    end

    def clean
      CleanOrder.add(:local_db_impl)
    end
  end

  # Section that selects LocalDBImpl at runtime
  class DatabaseSection < Taski::Section
    interfaces :connection_string

    def impl
      LocalDBImpl
    end

    def run
      RunOrder.add(:database_section)
      super
    end

    def clean
      CleanOrder.add(:database_section)
    end
  end

  # Main task that depends on the Section
  class MainTask < Taski::Task
    exports :result

    def run
      RunOrder.add(:main_task)
      @result = "Connected to: #{DatabaseSection.connection_string}"
    end

    def clean
      CleanOrder.add(:main_task)
    end
  end
end
