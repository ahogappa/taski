# frozen_string_literal: true

# Immutable render data passed to theme methods. Replaces the Liquid
# TaskDrop / ExecutionDrop / DataDrop (ThemeDrop has no successor: layouts
# call the theme instance directly).
#
# Deliberate differences from the drops:
# - every member is keyword-defaulted, so partial construction
#   (TaskInfo.new(stdout: line)) ports 1:1 from existing call sites;
# - unknown member access raises NoMethodError (drops returned nil for ANY
#   key); render isolation converts that into a blank line + a
#   Logging::Events::TEMPLATE_ERROR warning — typos become observable;
# - counts/total_duration default to 0 where unpassed drop keys read as nil.
#
# Data requires Ruby >= 3.2 — matches gemspec required_ruby_version.
# Instances are frozen.

module Taski
  module Progress
    # Per-task event data.
    #   name          [String, nil]  fully-qualified class name ("A::B::MyTask")
    #   state         [Symbol, nil]  :pending/:running/:completed/:failed/:skipped
    #   duration      [Float, Integer, nil] ms (Float .round(1) for runs,
    #                                Integer for groups), nil when N/A
    #   error_message [String, nil]  (currently always nil in shipped event flows)
    #   group_name    [String, nil]  group events only
    #   stdout        [String, nil]  last captured output line (execution_running only)
    TaskInfo = Data.define(:name, :state, :duration, :error_message, :group_name, :stdout) do
      def initialize(name: nil, state: nil, duration: nil, error_message: nil,
        group_name: nil, stdout: nil) = super
    end

    # Execution-level data, snapshotted under the layout monitor per render.
    #   state          [Symbol, nil]  :running/:completed/:failed
    #   *_count        [Integer]      tallies, default 0
    #   total_duration [Integer]      ms since execution start, default 0
    #   root_task_name [String, nil]
    #   task_names     [Array<String>, nil] active task names (execution_running only)
    #   spinner_index  [Integer]      spinner frame index at this render tick
    #                                 (snapshot of Layout::Base @spinner_index, default 0).
    #                                 Themes resolve the glyph via spinner_frame(index)
    #                                 so frame resolution stays inside render isolation.
    ExecutionInfo = Data.define(
      :state, :pending_count, :done_count, :completed_count, :failed_count,
      :skipped_count, :total_count, :total_duration, :root_task_name,
      :task_names, :spinner_index
    ) do
      def initialize(state: nil, pending_count: 0, done_count: 0, completed_count: 0,
        failed_count: 0, skipped_count: 0, total_count: 0, total_duration: 0,
        root_task_name: nil, task_names: nil, spinner_index: 0) = super
    end
  end
end
