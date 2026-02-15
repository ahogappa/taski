# frozen_string_literal: true

require "taski"

# Test fixtures for TaskProxy integration tests.
module TaskProxyFixtures
  # Leaf task returning a string
  class StringLeaf < Taski::Task
    exports :value

    def run
      @value = "hello"
    end
  end

  # Leaf task returning an integer
  class IntLeaf < Taski::Task
    exports :value

    def run
      @value = 42
    end
  end

  # Task that uses dep value in string interpolation
  class InterpolationTask < Taski::Task
    exports :value

    def run
      @value = "result: #{StringLeaf.value}"
    end
  end

  # Task that chains method calls on dep value
  class MethodChainTask < Taski::Task
    exports :value

    def run
      @value = StringLeaf.value.upcase
    end
  end

  # Task that directly assigns dep value to exported ivar
  class DirectAssignTask < Taski::Task
    exports :value

    def run
      @value = StringLeaf.value
    end
  end

  # Task that depends on multiple tasks
  class MultiDepTask < Taski::Task
    exports :value

    def run
      s = StringLeaf.value
      i = IntLeaf.value
      @value = "#{s}:#{i}"
    end
  end
end
