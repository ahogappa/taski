# frozen_string_literal: true

require "taski"

# Fixture tasks for StartDepAnalyzer tests.
# Only covers variable assignment patterns (current scope).
module StartDepAnalyzerFixtures
  class LeafTask < Taski::Task
    exports :value

    def run
      @value = "leaf"
    end
  end

  class LeafTaskB < Taski::Task
    exports :value

    def run
      @value = "leaf_b"
    end
  end

  # Pattern: a = Dep.value (local variable assignment)
  class LocalVarAssignment < Taski::Task
    exports :value

    def run
      a = LeafTask.value
      @value = a
    end
  end

  # Pattern: @value = Dep.value (instance variable assignment)
  class IvarAssignment < Taski::Task
    exports :value

    def run
      @value = LeafTask.value
    end
  end

  # Pattern: multiple assignments → both deps detected
  class MultipleAssignments < Taski::Task
    exports :value

    def run
      a = LeafTask.value
      b = LeafTaskB.value
      @value = "#{a}+#{b}"
    end
  end

  # Pattern: same class called twice → deduplicated to 1
  class DedupAssignment < Taski::Task
    exports :value

    def run
      a = LeafTask.value
      b = LeafTask.value
      @value = "#{a}+#{b}"
    end
  end

  # Pattern: non-dep assignment (a = 42) → scanning continues
  class NonDepAssignment < Taski::Task
    exports :value

    def run
      x = 42 # rubocop:disable Lint/UselessAssignment
      @value = LeafTask.value
    end
  end

  # Pattern: unknown pattern (if) stops scanning, only prior deps returned
  class UnknownPatternStops < Taski::Task
    exports :value

    def run
      a = LeafTask.value
      if true # rubocop:disable Lint/LiteralAsCondition
        LeafTaskB.value
      end
      @value = a
    end
  end

  # Pattern: namespaced constant (Module::Dep.value)
  class NamespacedConstant < Taski::Task
    exports :value

    def run
      @value = StartDepAnalyzerFixtures::LeafTask.value
    end
  end

  # Pattern: return stops scanning — deps after return not collected
  class ReturnStopsScanning < Taski::Task
    exports :value

    def run
      @value = LeafTask.value
      return
      @other = LeafTaskB.value # rubocop:disable Lint/UnreachableCode
    end
  end

  # === Phase 2: Danger pattern detection ===

  # Danger: proxy used as argument (0 == a → Integer#== receives proxy)
  class DangerArgComparison < Taski::Task
    exports :value

    def run
      a = LeafTask.value
      @value = (0 == a) # standard:disable Style/YodaCondition
    end
  end

  # Danger: proxy used as argument to include?
  class DangerArgInclude < Taski::Task
    exports :value

    def run
      a = LeafTask.value
      @value = [1, 2].include?(a)
    end
  end

  # Danger: b is argument, a is receiver (safe)
  class DangerArgMethodCall < Taski::Task
    exports :value

    def run
      a = LeafTask.value
      b = LeafTaskB.value
      @value = a.foo(b)
    end
  end

  # Danger: proxy used in if condition
  class DangerConditionIf < Taski::Task
    exports :value

    def run
      a = LeafTask.value
      if a # rubocop:disable Lint/LiteralAsCondition
        @value = "truthy"
      end
    end
  end

  # Danger: proxy used in unless condition
  class DangerConditionUnless < Taski::Task
    exports :value

    def run
      a = LeafTask.value
      unless a # rubocop:disable Lint/LiteralAsCondition
        @value = "falsy"
      end
    end
  end

  # Danger: proxy used in while condition
  class DangerConditionWhile < Taski::Task
    exports :value

    def run
      a = LeafTask.value
      while a # rubocop:disable Lint/LiteralAsCondition
        @value = "loop"
        break
      end
    end
  end

  # Danger: proxy used in until condition
  class DangerConditionUntil < Taski::Task
    exports :value

    def run
      a = LeafTask.value
      until a # rubocop:disable Lint/LiteralAsCondition
        @value = "loop"
        break
      end
    end
  end

  # Safe: proxy used as receiver only
  class SafeReceiverOnly < Taski::Task
    exports :value

    def run
      a = LeafTask.value
      @value = a.to_s
    end
  end

  # Safe: proxy used in string interpolation (to_s via method_missing)
  class SafeInterpolation < Taski::Task
    exports :value

    def run
      a = LeafTask.value
      @value = "result: #{a}"
    end
  end

  # Safe: ivar assignment (resolve_proxy_exports handles it)
  class SafeIvarAssignment < Taski::Task
    exports :value

    def run
      @value = LeafTask.value
    end
  end

  # Mixed: a is safe (receiver), b is danger (argument)
  class MixedSafeAndDanger < Taski::Task
    exports :value

    def run
      a = LeafTask.value
      b = LeafTaskB.value
      @value = a.foo(b)
    end
  end

  # Multiple danger uses: first use (condition) makes it danger
  class MultipleDangerUses < Taski::Task
    exports :value

    def run
      a = LeafTask.value
      if a # rubocop:disable Lint/LiteralAsCondition
        @value = a.to_s
      end
    end
  end

  # Unknown usage falls to sync (safety-first)
  class UnknownUsageFallsToSync < Taski::Task
    exports :value

    def run
      a = LeafTask.value
      @value = [a]
    end
  end

  # Safe: proxy reassigned to ivar
  class SafeReassignToIvar < Taski::Task
    exports :value

    def run
      a = LeafTask.value
      @value = a
    end
  end

  # Safe: proxy used as receiver in chained calls
  class SafeChainedReceiver < Taski::Task
    exports :value

    def run
      a = LeafTask.value
      @value = a.to_s.upcase
    end
  end

  # Safe: proxy assigned to non-exported ivar, used as receiver only
  class SafeNonExportedIvarReceiver < Taski::Task
    exports :value

    def run
      a = LeafTask.value
      @cache = a
      @value = @cache.to_s # receiver → safe
    end
  end

  # Safe: proxy assigned to exported ivar (resolve_proxy_exports handles it)
  class SafeExportedIvar < Taski::Task
    exports :value

    def run
      a = LeafTask.value
      @value = a # @value IS exported → safe
    end
  end

  # Safe: direct dep call assigned to non-exported ivar, used as receiver only
  class SafeDirectNonExportedIvar < Taski::Task
    exports :value

    def run
      @cache = LeafTask.value
      @value = @cache.to_s # receiver → safe
    end
  end

  # Danger: proxy in non-exported ivar used in condition
  class DangerNonExportedIvarCondition < Taski::Task
    exports :value

    def run
      a = LeafTask.value
      @flag = a
      if @flag # condition → unsafe
        @value = "truthy"
      end
    end
  end

  # Danger: proxy in non-exported ivar used as argument
  class DangerNonExportedIvarArgument < Taski::Task
    exports :value

    def run
      @data = LeafTask.value
      @value = [1, 2].include?(@data) # argument → unsafe
    end
  end

  # Danger: proxy assigned to an EXPORTED ivar, then read unsafely as an
  # argument before run returns. resolve_proxy_exports only fixes the final
  # stored value, so the proxy already passed into include? leaks unless the
  # dep is resolved synchronously.
  class DangerExportedIvarReadAsArgument < Taski::Task
    exports :value

    def run
      @value = LeafTask.value
      @flag = [1, 2].include?(@value) # exported ivar used as argument → unsafe
    end
  end

  # === W1/W2 wall fixtures ===
  #
  # The irreducible C-level walls where a live proxy silently misbehaves:
  #   W1 truthiness — if/unless/while/until/ternary predicate, && / || operands
  #   W2 === match  — case/when subject, case/in pattern subject
  # A proxy reaching any of these MUST be demoted to sync (resolved to the real
  # value). These fixtures pin that: both the classification (dep in sync_deps)
  # and the runtime result (no silent-wrong-result).

  # Leaf returning a falsy value, so &&/||/ternary leaks are observable.
  class FalseLeaf < Taski::Task
    exports :value

    def run
      @value = false
    end
  end

  # Leaf returning nil, for || fallback checks.
  class NilLeaf < Taski::Task
    exports :value

    def run
      @value = nil
    end
  end

  # W2: proxy as a `case ... when` subject (=== type match bypasses the proxy).
  class CaseWhenSubject < Taski::Task
    exports :value

    def run
      kind = LeafTask.value
      @value = case kind
      when String then "matched-String"
      else "no-match"
      end
    end
  end

  # W2: proxy as a `case ... in` (pattern match) subject.
  class CaseInSubject < Taski::Task
    exports :value

    def run
      kind = LeafTask.value
      @value = case kind
      in String then "matched-String"
      else "no-match"
      end
    end
  end

  # W1: proxy as the left operand of && (truthiness short-circuit).
  class AndOperand < Taski::Task
    exports :value

    def run
      flag = FalseLeaf.value
      @value = flag && "yes"
    end
  end

  # W1: proxy as the left operand of ||.
  class OrOperand < Taski::Task
    exports :value

    def run
      flag = NilLeaf.value
      @value = flag || "fallback"
    end
  end

  # W1: proxy as a ternary condition.
  class TernaryCondition < Taski::Task
    exports :value

    def run
      x = FalseLeaf.value
      @value = x ? "then-branch" : "else-branch"
    end
  end

  # W1 regression: proxy as the RIGHT operand of && inside an if-predicate.
  # (The naive "flag the left operand only" rule would miss this.)
  class IfWithNestedAnd < Taski::Task
    exports :value

    def run
      flag = FalseLeaf.value
      @value = if true && flag # standard:disable Lint/LiteralAsCondition
        "then-branch"
      else
        "else-branch"
      end
    end
  end

  # W1 regression: proxy as the MIDDLE operand of a chained &&.
  class ChainedAndMiddle < Taski::Task
    exports :value

    def run
      mid = FalseLeaf.value
      @value = true && mid && "c" # standard:disable Lint/LiteralAsCondition
    end
  end

  # NOT a wall: `!proxy` parses as a method call (`!`) with the proxy as the
  # RECEIVER, which TaskProxy#! resolves. So the dep stays a start_dep (proxy)
  # and `!false` is computed correctly — guards against wrongly demoting `!`.
  class NegationSafe < Taski::Task
    exports :value

    def run
      flag = FalseLeaf.value
      @value = !flag
    end
  end
end
