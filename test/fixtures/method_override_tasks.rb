# frozen_string_literal: true

require_relative "../../lib/taski"

module MethodOverrideFixtures
  # Use case 1: Fixed value without @var assignment
  class FixedValueTask < Taski::Task
    exports :timeout

    def timeout
      30
    end

    def run
    end
  end

  # Use case 2: Instance method used in both run and clean
  class SharedMethodTask < Taski::Task
    exports :connection

    def connection
      @connection ||= "db://localhost"
    end

    def run
      connection
    end

    def clean
      connection
    end
  end
end
