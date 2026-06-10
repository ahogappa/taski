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
end
