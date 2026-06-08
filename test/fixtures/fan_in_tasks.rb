# frozen_string_literal: true

require "taski"

# Fixtures for verifying that resolving many already-completed dependencies in a
# single task does not grow the worker call stack unboundedly.
#
# DeepFanInRoot reads Leaf.value many times inside a loop. The loop makes Leaf a
# synchronous (NeedDep) dependency; after the first resolution every subsequent
# read returns :completed. If each :completed read recurses into drive_fiber_loop
# instead of iterating, the worker stack grows one frame per read and overflows
# (SystemStackError, which is not a StandardError and so escapes the worker's
# rescue, killing the worker thread and hanging the executor).
module FanInFixtures
  class Leaf < Taski::Task
    exports :value

    def run
      @value = 1
    end
  end

  class DeepFanInRoot < Taski::Task
    exports :total

    READS = 50_000

    def run
      sum = 0
      READS.times { sum += Leaf.value }
      @total = sum
    end
  end
end
