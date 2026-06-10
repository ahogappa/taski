# frozen_string_literal: true

require "monitor"
require_relative "execution/task_observer"

module Taski
  # Execution profiling — a mirror for where the time went.
  #
  #   report = Taski.profile { Deploy.run }
  #   puts report
  #
  # The profile records task state transitions as a pure ADDITIONAL observer on
  # the executions started inside the block: execution behavior is completely
  # unchanged, and a profiling error can never break a run (observer dispatch
  # is error-isolated). The report shows each task's start offset and duration
  # plus the critical path, so a slow run explains itself — e.g. a dependency
  # that only started seconds into the run because it was read after inline
  # work.
  module Profile
    THREAD_LOCAL_KEY = :taski_profile_collector

    Event = Data.define(:task_class, :state, :phase, :at)
    Entry = Data.define(:name, :phase, :start_offset, :duration, :state)

    # Records task state transitions with timestamps. Registered automatically
    # (via ExecutionFacade.build_default) on every execution started while a
    # Taski.profile block is running on this fiber.
    class Collector < Execution::TaskObserver
      def initialize
        super
        @monitor = Monitor.new
        @events = []
        @root = nil
        @graph = nil
      end

      def on_ready
        @monitor.synchronize do
          @root ||= context&.root_task_class
          @graph ||= context&.dependency_graph
        end
      end

      def on_task_updated(task_class, previous_state:, current_state:, phase:, timestamp:)
        @monitor.synchronize do
          @events << Event.new(task_class: task_class, state: current_state, phase: phase, at: timestamp)
        end
      end

      def snapshot
        @monitor.synchronize { {events: @events.dup, root: @root, graph: @graph} }
      end
    end

    # The profile result: per-task timing entries (sorted by start), the
    # critical path from the root, and the block's return value.
    class Report
      attr_reader :tasks, :critical_path, :result, :root_name, :total

      def self.build(collector, result:)
        snap = collector.snapshot
        new(events: snap[:events], root: snap[:root], graph: snap[:graph], result: result)
      end

      def initialize(events:, root:, graph:, result:)
        @result = result
        @root_name = root && (root.name || root.inspect)
        t0 = events.map(&:at).min
        intervals = build_intervals(events)
        @tasks = build_entries(intervals, t0).freeze
        finishes = intervals.values.flatten.filter_map { |iv| iv[:finish] }
        # total is the SPAN from the first task start to the last task finish
        # inside the block — for a block with multiple runs it includes any
        # time between them.
        @total = (t0 && !finishes.empty?) ? finishes.max - t0 : nil
        @critical_path = compute_critical_path(root, graph, intervals, t0).freeze
      end

      def empty?
        @tasks.empty?
      end

      def to_s
        return "Taski profile — no execution recorded\n" if empty?

        lines = []
        lines << format("Taski profile — root: %s, total: %s, tasks: %d", @root_name || "?", fmt_duration(@total), @tasks.size)
        lines << ""
        lines << "  start      duration   task"
        @tasks.each do |t|
          label = (t.phase == :clean) ? "#{t.name} (clean)" : t.name
          lines << format("  %-10s %-10s %s%s", fmt_offset(t.start_offset), fmt_duration(t.duration), label, state_note(t.state))
        end
        unless @critical_path.empty?
          lines << ""
          lines << "critical path:"
          @critical_path.each_with_index do |t, i|
            prefix = (i == 0) ? "  " : "  #{"  " * (i - 1)}└ "
            lines << format("%s%s (started %s, ran %s)", prefix, t.name, fmt_offset(t.start_offset), fmt_duration(t.duration))
          end
        end
        lines.join("\n") + "\n"
      end

      private

      # Build {[task_class, phase] => [{start:, finish:, state:}]} from the
      # event stream. Re-runs of the same class produce additional intervals.
      def build_intervals(events)
        intervals = Hash.new { |h, k| h[k] = [] }
        events.sort_by(&:at).each do |ev|
          key = [ev.task_class, ev.phase]
          case ev.state
          when :running
            intervals[key] << {start: ev.at, finish: nil, state: :running}
          when :completed, :failed
            open = intervals[key].reverse_each.find { |iv| iv[:finish].nil? }
            if open
              open[:finish] = ev.at
              open[:state] = ev.state
            else
              intervals[key] << {start: nil, finish: ev.at, state: ev.state}
            end
          when :skipped
            # A :skipped event can arrive for a class that demonstrably ran —
            # the outer executor marks graph members it never started itself,
            # even when they ran via a nested execution on the same facade.
            # Don't let one timeline assert both "completed" and "skipped".
            unless intervals[key].any? { |iv| iv[:start] }
              intervals[key] << {start: nil, finish: nil, state: :skipped}
            end
          end
        end
        intervals
      end

      def build_entries(intervals, t0)
        entries = intervals.flat_map do |(task_class, phase), ivs|
          ivs.map do |iv|
            Entry.new(
              name: task_class.name || task_class.inspect,
              phase: phase,
              start_offset: iv[:start] && t0 && (iv[:start] - t0),
              duration: (iv[:start] && iv[:finish]) ? iv[:finish] - iv[:start] : nil,
              state: iv[:state]
            )
          end
        end
        entries.sort_by { |e| [e.start_offset ? 0 : 1, e.start_offset || 0.0] }
      end

      # Walk from the root, at each step descending into the dependency whose
      # run finished last — the chain that bounded the wall-clock time. An
      # approximation (it uses the static graph plus observed intervals), but
      # an honest one: each hop's "started +X" shows where serialization began.
      def compute_critical_path(root, graph, intervals, t0)
        return [] unless root && graph && t0

        path = []
        visited = Set.new
        current = root
        while current && visited.add?(current)
          # Render the interval that actually bounded the wall clock (the one
          # with the latest finish), not merely the first recorded one.
          ivs = (intervals[[current, :run]] || []).select { |i| i[:start] }
          break if ivs.empty?
          iv = ivs.max_by { |i| i[:finish] || -Float::INFINITY }

          path << Entry.new(
            name: current.name || current.inspect,
            phase: :run,
            start_offset: iv[:start] - t0,
            duration: iv[:finish] ? iv[:finish] - iv[:start] : nil,
            state: iv[:state]
          )
          deps = graph.dependencies_for(current)
          break unless deps

          current = deps.select { |d| (intervals[[d, :run]] || []).any? { |i| i[:finish] } }
            .max_by { |d| intervals[[d, :run]].filter_map { |i| i[:finish] }.max }
        end
        path
      end

      def fmt_offset(seconds)
        seconds ? format("+%.3fs", seconds) : "—"
      end

      def fmt_duration(seconds)
        seconds ? format("%.3fs", seconds) : "—"
      end

      def state_note(state)
        case state
        when :failed then "  (failed)"
        when :skipped then "  (skipped)"
        when :running then "  (never finished)"
        else ""
        end
      end
    end
  end

  # Profile the executions started inside the block (on this fiber) and return
  # a Profile::Report. Purely observational: execution behavior is unchanged,
  # and without a profile block nothing is recorded. The block's return value
  # is available as +report.result+. If the block raises (e.g. a failing run),
  # the exception propagates and no report is returned.
  #
  # Scope notes:
  # - Observes executions started directly on the calling fiber (.run/.value).
  #   An execution started INSIDE a task body reuses the enclosing execution's
  #   facade, so its events land in the enclosing profile; runs started on
  #   threads you spawn yourself are not observed.
  # - Nested profile blocks do not compose: the inner block takes over
  #   recording for its duration (the outer report omits that span).
  # - If the block starts multiple executions, all tasks share one timeline;
  #   the root and critical path reflect the first execution, and +total+ is
  #   the span from first task start to last finish (including gaps).
  def self.profile
    collector = Profile::Collector.new
    previous = Thread.current[Profile::THREAD_LOCAL_KEY]
    Thread.current[Profile::THREAD_LOCAL_KEY] = collector
    result = yield
    begin
      Profile::Report.build(collector, result: result)
    rescue => e
      # The run already succeeded — a report-construction bug must not turn
      # that into a failure. Degrade to an empty report and surface the error.
      Taski::Logging.warn(
        Taski::Logging::Events::PROFILE_ERROR,
        error_class: e.class.name,
        error_message: e.message
      )
      Profile::Report.new(events: [], root: nil, graph: nil, result: result)
    end
  ensure
    Thread.current[Profile::THREAD_LOCAL_KEY] = previous
  end

  # The active profile collector for this fiber, if a Taski.profile block is
  # running (used by ExecutionFacade.build_default).
  # @api private
  def self.current_profile_collector
    Thread.current[Profile::THREAD_LOCAL_KEY]
  end
end
