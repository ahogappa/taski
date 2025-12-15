# frozen_string_literal: true

require "taski"

# Test fixtures for circular dependency detection

# Direct circular dependency: A <-> B
class CircularTaskA < Taski::Task
  exports :value

  def run
    @value = "A: #{CircularTaskB.value}"
  end
end

class CircularTaskB < Taski::Task
  exports :value

  def run
    @value = "B: #{CircularTaskA.value}"
  end
end

# Indirect circular dependency: X -> Y -> Z -> X
module IndirectCircular
  class TaskX < Taski::Task
    exports :value

    def run
      @value = "X: #{TaskY.value}"
    end
  end

  class TaskY < Taski::Task
    exports :value

    def run
      @value = "Y: #{TaskZ.value}"
    end
  end

  class TaskZ < Taski::Task
    exports :value

    def run
      @value = "Z: #{TaskX.value}"
    end
  end
end
