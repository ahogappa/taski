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
end
