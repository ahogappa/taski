# frozen_string_literal: true

require "taski"

# Test fixtures for executor and scheduler tests.
# Named classes enable Prism AST static analysis to detect dependencies.
module ExecutorFixtures
  # Leaf task with no dependencies
  class SingleTask < Taski::Task
    exports :value

    def run
      @value = "result_value"
    end
  end

  # Linear chain: ChainRoot -> ChainMiddle -> ChainLeaf
  class ChainLeaf < Taski::Task
    exports :value

    def run
      @value = "C"
    end
  end

  class ChainMiddle < Taski::Task
    exports :value

    def run
      @value = "B->#{ChainLeaf.value}"
    end
  end

  class ChainRoot < Taski::Task
    exports :value

    def run
      @value = "A->#{ChainMiddle.value}"
    end
  end

  # Diamond: DiamondRoot -> [DiamondLeft, DiamondRight] -> DiamondLeaf
  class DiamondLeaf < Taski::Task
    exports :value

    def run
      @value = "C"
    end
  end

  class DiamondLeft < Taski::Task
    exports :value

    def run
      @value = "A(#{DiamondLeaf.value})"
    end
  end

  class DiamondRight < Taski::Task
    exports :value

    def run
      @value = "B(#{DiamondLeaf.value})"
    end
  end

  class DiamondRoot < Taski::Task
    exports :value

    def run
      a = DiamondLeft.value
      b = DiamondRight.value
      @value = "Root(#{a}, #{b})"
    end
  end

  # Independent parallel tasks with sleep
  class ParallelA < Taski::Task
    exports :value

    def run
      sleep 0.1
      @value = "A"
    end
  end

  class ParallelB < Taski::Task
    exports :value

    def run
      sleep 0.1
      @value = "B"
    end
  end

  class ParallelRoot < Taski::Task
    exports :value

    def run
      a = ParallelA.value
      b = ParallelB.value
      @value = "#{a}+#{b}"
    end
  end

  # Task that raises an error
  class ErrorTask < Taski::Task
    exports :value

    def run
      raise StandardError, "fiber error"
    end
  end

  # Conditional dependency: ConditionalMain references ConditionalDep in `if false`
  # Prism AST detects the reference, but at runtime the branch is never taken
  class ConditionalDep < Taski::Task
    exports :value

    def run
      @value = "should_not_run"
    end
  end

  class ConditionalMain < Taski::Task
    exports :value

    def run
      if false # rubocop:disable Lint/LiteralAsCondition
        ConditionalDep.value
      end
      @value = "no_dep"
    end
  end

  # Multiple exported methods
  class MultiExportDep < Taski::Task
    exports :first_name, :age

    def run
      @first_name = "Alice"
      @age = 30
    end
  end

  class MultiExportMain < Taski::Task
    exports :value

    def run
      n = MultiExportDep.first_name
      a = MultiExportDep.age
      @value = "#{n}:#{a}"
    end
  end

  # Dependency error propagation
  class FailingDep < Taski::Task
    exports :value

    def run
      raise StandardError, "dep failed"
    end
  end

  class DepErrorMain < Taski::Task
    exports :value

    def run
      FailingDep.value
      @value = "should not reach"
    end
  end

  # Skipped task verification: SkippedRoot -> SkippedMiddle -> SkippedSlowLeaf
  # Root completes without accessing SkippedMiddle, so middle is skipped.
  # The `if false` block ensures static analysis still sees the dependency.
  class SkippedSlowLeaf < Taski::Task
    exports :value

    def run
      sleep 0.2
      @value = "leaf"
    end
  end

  class SkippedMiddle < Taski::Task
    exports :value

    def run
      @value = "middle(#{SkippedSlowLeaf.value})"
    end
  end

  class SkippedRoot < Taski::Task
    exports :value

    def run
      if false # rubocop:disable Lint/LiteralAsCondition
        SkippedMiddle.value
      end
      @value = "root_done"
    end
  end
end
