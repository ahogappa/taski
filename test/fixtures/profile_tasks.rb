# frozen_string_literal: true

require "taski"

# Fixtures for Taski.profile: known sleep durations so the report's intervals
# and critical path are assertable with generous margins.
module ProfileFixtures
  class SlowDepA < Taski::Task
    exports :value

    def run
      sleep 0.25
      @value = "a"
    end
  end

  class SlowDepB < Taski::Task
    exports :value

    def run
      sleep 0.4
      @value = "b"
    end
  end

  # Both deps are leading prefix reads -> prestarted -> run in parallel.
  # Critical path: ParallelRoot <- SlowDepB (the slower dep).
  class ParallelRoot < Taski::Task
    exports :value

    def run
      a = SlowDepA.value
      b = SlowDepB.value
      @value = "#{a}#{b}"
    end
  end

  # The bare sleep stops phase-1, so SlowDepA is NOT prestarted: it starts only
  # when read, ~0.3s into the run — the late-start (S3) shape the profile
  # exists to surface.
  class LazyRoot < Taski::Task
    exports :value

    def run
      sleep 0.3
      v = SlowDepA.value
      @value = "lazy: #{v}"
    end
  end

  # Raises after a short sleep — for failed-state reporting.
  class FailingRoot < Taski::Task
    exports :value

    def run
      sleep 0.05
      raise "profile failing fixture"
    end
  end

  # run + clean pair — for clean-phase entries in the report.
  class CleanDep < Taski::Task
    exports :value

    def run
      @value = "dep"
    end

    def clean
      sleep 0.02
    end
  end

  class CleanRoot < Taski::Task
    exports :value

    def run
      v = CleanDep.value
      @value = "root: #{v}"
    end

    def clean
      sleep 0.02
    end
  end

  # Run succeeds but clean fails — the run-phase profile must still be written.
  class FailingCleanRoot < Taski::Task
    exports :value

    def run
      @value = "ok"
    end

    def clean
      raise "clean fails"
    end
  end

  # Calls a nested run(profile:) from INSIDE its own run body — a nested
  # execution joins the enclosing one, so a separate profile cannot exist.
  class NestedProfilingRoot < Taski::Task
    exports :value

    class << self
      attr_accessor :destination
    end

    def run
      CleanDep.run(profile: self.class.destination)
      @value = "nested-done"
    end
  end
end
