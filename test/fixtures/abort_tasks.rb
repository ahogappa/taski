# frozen_string_literal: true

require "taski"

# Fixtures for verifying that aborting one task does not deadlock the executor
# when a sibling task is dropped (its drive_fiber early-returns on abort).
#
# With workers: 1 the schedule is deterministic:
#   1. AbortRoot prestarts Aborter (first) then Victim.
#   2. Aborter is dequeued first, runs, and raises TaskAbortException (sets the
#      abort flag).
#   3. AbortRoot's run body resolves the Victim proxy in the interpolation and
#      parks waiting on Victim.
#   4. Victim is dequeued next; drive_fiber sees abort_requested? and drops it.
#
# Without a terminal event for the dropped Victim, AbortRoot is parked forever
# and the executor's main loop blocks on completion_queue.pop (deadlock).
module AbortFixtures
  class Aborter < Taski::Task
    exports :value

    def run
      raise Taski::TaskAbortException, "abort now"
    end
  end

  class Victim < Taski::Task
    exports :value

    def run
      @value = "victim ran"
    end
  end

  class AbortRoot < Taski::Task
    exports :value

    def run
      _aborter = Aborter.value # prestarted, runs first and aborts (never resolved here)
      v = Victim.value
      @value = v.to_s
    end
  end
end
