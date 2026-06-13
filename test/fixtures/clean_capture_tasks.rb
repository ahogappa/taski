# frozen_string_literal: true

require "taski"

# Fixtures for the clean-phase output-capture contract: run_and_clean shares
# one ExecutionFacade across both phases, but each phase sets up and tears
# down its own output router. The layout must re-adopt the clean-phase router
# at the clean-phase on_ready (see test_clean_phase_output_capture.rb).
module CleanCaptureFixtures
  class Leaf < Taski::Task
    exports :value

    def run
      puts "run output"
      sleep 0.3
      @value = 1
    end

    def clean
      puts "clean output"
      # Give the router's async poll thread time to drain the line before the
      # clean-completed event, so the test reads it deterministically (mirrors
      # the run phase; the poll interval is ~0.1s).
      sleep 0.3
    end
  end
end
