# frozen_string_literal: true

require "taski"

# Fixtures for the speculative-task completion guarantee: a prestarted task
# that is parked on a slow dep when the root finishes must still run to
# completion (its ensure must execute) before run() returns.
module SpeculativeCompletionFixtures
  class SlowInner < Taski::Task
    exports :value

    def run
      sleep 0.4
      @value = "inner"
    end
  end

  # Prestarted by FastRoot. Reads SlowInner with a phase-2 sync demotion
  # (argument use), so SlowInner is prestarted AND the read parks on the
  # already-running dep — putting this task in the parked state when the
  # root completes.
  class SpeculativeOuter < Taski::Task
    exports :value

    class << self
      attr_accessor :completed, :ensure_ran
    end

    def run
      v = SlowInner.value
      @match = ["inner"].include?(v)
      self.class.completed = true
      @value = "outer: #{v}"
    ensure
      self.class.ensure_ran = true
    end
  end

  # Completes immediately: reads SpeculativeOuter as a proxy that is never
  # forced (stored in a non-exported ivar), so nothing in this task ever
  # waits for the speculative chain.
  class FastRoot < Taski::Task
    exports :value

    def run
      a = SpeculativeOuter.value
      @hold = a
      @value = "fast"
    end
  end
end
