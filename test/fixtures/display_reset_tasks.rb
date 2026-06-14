# frozen_string_literal: true

require "taski"

# Two independent single-task roots used to prove the progress display resets
# its per-execution state between sequential top-level executions in the same
# process (see test_display_reset_between_executions.rb). Each run is one task,
# so a correct display shows "1/1 tasks" for each — accumulation or a stale
# root name is the bug.
module DisplayResetFixtures
  class FirstRoot < Taski::Task
    exports :value

    def run
      @value = :first
    end
  end

  class SecondRoot < Taski::Task
    exports :value

    def run
      @value = :second
    end
  end
end
