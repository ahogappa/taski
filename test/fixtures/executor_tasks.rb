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

  # Failure cascade: FailCascadeRoot -> [FailCascadeBranchA, FailCascadeBranchB]
  #   FailCascadeBranchA -> FailCascadeLeaf (fails)
  #   FailCascadeBranchB -> FailCascadeMiddle -> FailCascadeLeaf (fails)
  # When leaf fails, middle and branch_b are cascade-skipped.
  class FailCascadeLeaf < Taski::Task
    exports :value
    def run = raise StandardError, "leaf failed"
  end

  class FailCascadeMiddle < Taski::Task
    exports :value

    def run
      @value = "m(#{FailCascadeLeaf.value})"
    end
  end

  class FailCascadeBranchA < Taski::Task
    exports :value

    def run
      @value = "a(#{FailCascadeLeaf.value})"
    end
  end

  class FailCascadeBranchB < Taski::Task
    exports :value

    def run
      @value = "b(#{FailCascadeMiddle.value})"
    end
  end

  class FailCascadeRoot < Taski::Task
    exports :value

    def run
      a = FailCascadeBranchA.value
      b = FailCascadeBranchB.value
      @value = "#{a}+#{b}"
    end
  end

  # Unreached subtree: UnreachedRoot -> UnreachedParent -> UnreachedChild -> UnreachedSlowLeaf
  # Root completes immediately without accessing the chain.
  # `if false` ensures static analysis sees the dependency.
  class UnreachedSlowLeaf < Taski::Task
    exports :value

    def run
      sleep 0.3
      @value = "slow"
    end
  end

  class UnreachedChild < Taski::Task
    exports :value

    def run
      @value = UnreachedSlowLeaf.value
    end
  end

  class UnreachedParent < Taski::Task
    exports :value

    def run
      @value = UnreachedChild.value
    end
  end

  class UnreachedRoot < Taski::Task
    exports :value

    def run
      if false # rubocop:disable Lint/LiteralAsCondition
        UnreachedParent.value
      end
      @value = "done"
    end
  end

  # Two branches sharing a failing leaf: FailBranchRoot -> [FailBranchStarted, FailBranchUnstarted]
  # Both branches depend on FailBranchLeaf (fails).
  # Root yields for Started first; Unstarted stays pending -> cascade-skipped.
  class FailBranchLeaf < Taski::Task
    exports :value
    def run = raise StandardError, "boom"
  end

  class FailBranchStarted < Taski::Task
    exports :value

    def run
      @value = FailBranchLeaf.value
    end
  end

  class FailBranchUnstarted < Taski::Task
    exports :value

    def run
      @value = FailBranchLeaf.value
    end
  end

  class FailBranchRoot < Taski::Task
    exports :value

    def run
      a = FailBranchStarted.value
      b = FailBranchUnstarted.value
      @value = "#{a}+#{b}"
    end
  end

  # Deep subtree failure: FailSubtreeRoot -> [FailSubtreeStartedBranch, FailSubtreeDeepBranch]
  #   FailSubtreeStartedBranch -> FailSubtreeLeaf (fails)
  #   FailSubtreeDeepBranch -> FailSubtreeMiddle -> FailSubtreeLeaf (fails)
  # middle and deep_branch are cascade-skipped.
  class FailSubtreeLeaf < Taski::Task
    exports :value
    def run = raise("fail")
  end

  class FailSubtreeStartedBranch < Taski::Task
    exports :value

    def run
      @value = FailSubtreeLeaf.value
    end
  end

  class FailSubtreeMiddle < Taski::Task
    exports :value

    def run
      @value = FailSubtreeLeaf.value
    end
  end

  class FailSubtreeDeepBranch < Taski::Task
    exports :value

    def run
      @value = FailSubtreeMiddle.value
    end
  end

  class FailSubtreeRoot < Taski::Task
    exports :value

    def run
      a = FailSubtreeStartedBranch.value
      b = FailSubtreeDeepBranch.value
      @value = "#{a}+#{b}"
    end
  end

  # Clean skip: CleanSkipRoot -> [CleanSkipGoodDep, CleanSkipSkippedDep -> CleanSkipFailingDep]
  # Root completes without accessing dependencies. FailingDep raises -> SkippedDep cascade-skipped.
  # Verifies skipped tasks' clean method is NOT called.
  class CleanSkipGoodDep < Taski::Task
    exports :value
    def run = @value = "good"
    def clean = nil
  end

  class CleanSkipFailingDep < Taski::Task
    exports :value
    def run = raise "boom"
    def clean = nil
  end

  class CleanSkipSkippedDep < Taski::Task
    exports :value

    def run
      @value = CleanSkipFailingDep.value
    end

    def clean = nil
  end

  class CleanSkipRoot < Taski::Task
    exports :value

    def run
      if false # rubocop:disable Lint/LiteralAsCondition
        CleanSkipGoodDep.value
        CleanSkipSkippedDep.value
      end
      @value = "done"
    end

    def clean = nil
  end

  # Failed task clean: FailCleanRoot -> FailCleanDep (raises)
  # Verifies failed tasks' clean method IS called for resource release.
  class FailCleanDep < Taski::Task
    exports :value
    def run = raise "boom"
    def clean = nil
  end

  class FailCleanRoot < Taski::Task
    exports :value

    def run
      @value = FailCleanDep.value
    end

    def clean = nil
  end
end
