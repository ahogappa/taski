# frozen_string_literal: true

require "taski"

# Fixtures for AggregateError attribution: a dependency failure propagates up
# the requester chain (every waiter re-raises the same error object), and the
# deduplicated TaskFailure must name the ORIGIN task — the one whose run
# raised — not whichever requester happened to be registered first.
module AttributionFixtures
  # The origin: its own run raises.
  class OriginFail < Taski::Task
    exports :value

    def run
      raise "origin boom"
    end
  end

  # Re-raises OriginFail's error when the pull fails.
  class MiddleRequester < Taski::Task
    exports :value

    def run
      @value = "mid: #{OriginFail.value}"
    end
  end

  class ChainRoot < Taski::Task
    exports :value

    def run
      @value = "root: #{MiddleRequester.value}"
    end
  end

  # Two independent origins read by one root — the GUIDE Error Handling shape.
  class IndependentFailA < Taski::Task
    exports :value

    def run
      raise "A failed"
    end
  end

  class IndependentFailB < Taski::Task
    exports :value

    def run
      raise "B failed"
    end
  end

  class FanInRoot < Taski::Task
    exports :value

    def run
      a = IndependentFailA.value
      b = IndependentFailB.value
      @value = "#{a}#{b}"
    end
  end

  # Nested executor: the outer task's body starts a whole inner execution.
  # The inner executor raises an AggregateError already attributed to
  # InnerLeaf; the outer executor splices those failures through.
  class InnerLeaf < Taski::Task
    exports :value

    def run
      raise "inner boom"
    end
  end

  class InnerRoot < Taski::Task
    exports :value

    def run
      @value = "inner: #{InnerLeaf.value}"
    end
  end

  class NestedOuter < Taski::Task
    exports :value

    def run
      # Bare call statement (not an assignment): phase-1 static analysis stops
      # here, so InnerRoot is not prestarted by the outer execution — it runs
      # purely as a nested executor inside this body.
      InnerRoot.run
      @value = "outer done"
    end
  end
end
