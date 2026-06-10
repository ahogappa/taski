# frozen_string_literal: true

require "taski"

# Fixtures for the skipped-task revival contract: a task reported :skipped
# (because a dependency failed) can later be requested by a still-running
# task via the Fiber pull model — it then runs normally. The sequence
# skipped → running → completed is legal and pinned by test_skip_revival.rb.
module SkipRevivalFixtures
  # Fails quickly, triggering the skip cascade for its dependents.
  class ReviveFailLeaf < Taski::Task
    exports :value

    def run
      sleep 0.05
      raise "fast fail"
    end
  end

  # Statically depends on ReviveFailLeaf (the branch read is a graph edge) so
  # the skip cascade marks it skipped — but at runtime the branch is never
  # taken, so when revived it completes without touching the failed dep.
  class ReviveShared < Taski::Task
    exports :value

    def run
      @value = "shared"
      if @value.empty?
        x = ReviveFailLeaf.value
        @extra = "never: #{x}"
      end
      @value
    end
  end

  # Reads ReviveShared only AFTER the cutoff (the bare sleep), long after the
  # skip cascade ran — this pull is what revives the skipped task.
  class ReviveSlowRequester < Taski::Task
    exports :value

    def run
      sleep 0.6
      @value = "req: #{ReviveShared.value}"
    end
  end

  class ReviveRoot < Taski::Task
    exports :value

    def run
      f = ReviveFailLeaf.value
      r = ReviveSlowRequester.value
      @hold = f
      @value = "root: #{r}"
    end
  end
end
