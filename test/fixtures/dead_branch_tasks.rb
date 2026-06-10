# frozen_string_literal: true

require "taski"

# Fixtures for the dead-branch prestart regression: a dep that is referenced
# ONLY inside a never-taken branch (and used "unsafely" there, so phase-2's
# whole-body scan flags it) must NOT be speculatively executed — sequential
# semantics never reach its read.
module DeadBranchFixtures
  class Leaf < Taski::Task
    exports :value

    def run
      @value = "leaf"
    end
  end

  # Records whether it ever executed, so tests can assert it did NOT.
  class DeadProbe < Taski::Task
    exports :value

    class << self
      attr_accessor :ran
    end

    def run
      self.class.ran = true
      @value = "dead-probe"
    end
  end

  # Raises if it ever executes — a run that never reads it must still succeed.
  class RaisingDead < Taski::Task
    exports :value

    def run
      raise "executed a dep that is only referenced in a dead branch"
    end
  end

  # The branch condition is false at runtime ("leaf" is not empty), so the
  # branch body — where DeadProbe is read and passed as an argument (an
  # "unsafe" use that phase-2 flags) — never executes.
  class DeadBranchRoot < Taski::Task
    exports :value

    def run
      a = Leaf.value
      if a.to_s.empty?
        x = DeadProbe.value
        @flag = [1].include?(x)
      end
      @value = "root: #{a}"
    end
  end

  # Same shape, but the dead-branch dep raises when executed. Sequential
  # semantics succeed (the branch is never taken), so the run must succeed.
  class DeadBranchRaisingRoot < Taski::Task
    exports :value

    def run
      a = Leaf.value
      if a.to_s.empty?
        x = RaisingDead.value
        @flag = [1].include?(x)
      end
      @value = "ok: #{a}"
    end
  end
end
