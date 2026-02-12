# frozen_string_literal: true

require "taski"

# Integration test fixtures for start_dep-driven parallel execution.
module StartDepFixtures
  # Two independent deps with sleep — verifies parallel execution via start_dep
  class SlowDepA < Taski::Task
    exports :value

    def run
      sleep 0.1
      @value = "A"
    end
  end

  class SlowDepB < Taski::Task
    exports :value

    def run
      sleep 0.1
      @value = "B"
    end
  end

  class ParallelStartDepRoot < Taski::Task
    exports :value

    def run
      a = SlowDepA.value
      b = SlowDepB.value
      @value = "#{a}+#{b}"
    end
  end

  # if false branch — dep must NOT be executed
  class GuardedDep < Taski::Task
    exports :value

    def run
      @value = "should_not_run"
    end
  end

  class IfFalseRoot < Taski::Task
    exports :value

    def run
      if false # rubocop:disable Lint/LiteralAsCondition
        GuardedDep.value
      end
      @value = "safe"
    end
  end

  # begin/rescue/ensure pattern
  class EnsureDep < Taski::Task
    exports :value

    def run
      @value = "ensure_val"
    end
  end

  class RescueDep < Taski::Task
    exports :value

    def run
      @value = "rescue_val"
    end
  end

  class BeginDep < Taski::Task
    exports :value

    def run
      @value = "begin_val"
    end
  end

  class BeginRescueEnsureRoot < Taski::Task
    exports :value

    def run
      begin
        v = BeginDep.value
      rescue
        v = RescueDep.value
      ensure
        EnsureDep.value
      end
      @value = v
    end
  end

  # Dynamic const_get fallback — deps resolved via Fiber pull only
  class DynamicDep < Taski::Task
    exports :value

    def run
      @value = "dynamic_result"
    end
  end

  class ConstGetRoot < Taski::Task
    exports :value

    def run
      klass = Object.const_get("StartDepFixtures::DynamicDep")
      @value = klass.value
    end
  end
end
