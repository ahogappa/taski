# frozen_string_literal: true

require "taski"

# Fixtures for verifying dependency resolution when a class is defined with a
# compact path (`class Outer::Consumer`) rather than nested `module`/`class`.
# The sibling dependency `Dep` is referenced unqualified inside run and must be
# resolved relative to the Outer namespace.
module CompactPath
  class Dep < Taski::Task
    exports :value

    def run
      @value = "dep"
    end
  end
end

class CompactPath::Consumer < Taski::Task
  exports :value

  def run
    @value = "consumer: #{Dep.value}"
  end
end
