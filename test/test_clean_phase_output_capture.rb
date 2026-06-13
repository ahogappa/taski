# frozen_string_literal: true

require "test_helper"
require "taski/progress/layout/base"
require_relative "fixtures/clean_capture_tasks"

# End-to-end pin for the clean-phase output-capture contract through the real
# executor: run_and_clean reuses ONE ExecutionFacade across both phases, but
# the run phase tears down its output router and the clean phase builds a
# fresh one. The display layer must re-adopt the clean-phase router so the
# status line shows live clean-phase output instead of reading the dead
# run-phase router.
class TestCleanPhaseOutputCapture < Minitest::Test
  # A layout that records, at every on_ready and every render, which output
  # router it currently holds and what last line that router reports for the
  # task. (Non-TTY so it never starts a render thread; we read state directly.)
  class RecordingLayout < Taski::Progress::Layout::Base
    def self.build(output: $stderr, theme: nil)
      new(output: output, theme: theme)
    end

    attr_reader :ready_captures, :clean_last_lines

    def initialize(output: $stderr, theme: nil)
      super
      @ready_captures = []
      @clean_last_lines = []
    end

    def on_ready
      super
      @monitor.synchronize { @ready_captures << @output_capture }
    end

    # Records the clean-phase output the router exposes as it completes a task.
    def handle_task_update(task_class, current_state, phase)
      if phase == :clean && current_state == :completed
        @clean_last_lines << @output_capture&.last_line_for(task_class)
      end
      super
    end
  end

  def setup
    Taski::Task.reset! if defined?(Taski::Task)
    Taski::StaticAnalysis::StartDepAnalyzer.clear_cache!
    @saved = Taski.progress_display
    Taski.progress.layout = RecordingLayout
  end

  def teardown
    Taski.reset_progress_display!
  end

  def test_clean_phase_router_is_adopted_and_shows_clean_output
    CleanCaptureFixtures::Leaf.run_and_clean

    layout = Taski.progress_display
    refute_nil layout, "the recording layout must be the active display"

    # on_ready fires once per phase on the shared facade; the run-phase router
    # and the clean-phase router are distinct objects, both real.
    captures = layout.ready_captures.compact
    assert_equal 2, captures.size, "expected an on_ready for both run and clean phases"
    refute_same captures[0], captures[1],
      "the clean phase rebuilds the router — the layout must adopt the new one"

    # The adopted clean-phase router reports the clean-phase output line, not a
    # stale run-phase line (the bug: the layout kept reading the dead run router).
    assert_includes layout.clean_last_lines.compact, "clean output",
      "the status line must read the clean-phase router's live output"
    refute_includes layout.clean_last_lines.compact, "run output",
      "the clean phase must not read the dead run-phase router"
  end
end
