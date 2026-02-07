# frozen_string_literal: true

require "taski"

# Test fixtures for logging tests.
module LoggingFixtures
  # Simple task for basic logging event tests
  class SimpleTask < Taski::Task
    def run
      "result"
    end
  end

  # Task that raises an error
  class FailingTask < Taski::Task
    def run
      raise "intentional error"
    end
  end

  # Task with both run and clean methods
  class CleanableTask < Taski::Task
    def run
      "result"
    end

    def clean
      "cleaned"
    end
  end

  # Dependency pair for dependency.resolved event testing
  class DepTask < Taski::Task
    exports :value

    def run
      @value = "dep_value"
    end
  end

  class RootWithDep < Taski::Task
    exports :result

    def run
      @result = DepTask.value
    end
  end
end
