# frozen_string_literal: true

require_relative "base_progress_display"

module Taski
  module Execution
    # PlainProgressDisplay provides plain text output without terminal escape codes.
    # Designed for non-TTY environments (CI, log files, piped output).
    #
    # Output format:
    #   [START] TaskName
    #   [DONE] TaskName (123.4ms)
    #   [FAIL] TaskName: Error message
    #
    # Enable with: TASKI_PROGRESS_MODE=plain
    class PlainProgressDisplay < BaseProgressDisplay
      def initialize(output: $stderr)
        super
        @output.sync = true if @output.respond_to?(:sync=)
        @enabled = @output.tty? || ENV["TASKI_FORCE_PROGRESS"] == "1"
      end

      protected

      # Template method: Called when a section impl is registered
      def on_section_impl_registered(section_class, impl_class)
        # Ensure impl is registered
        unless @tasks.key?(impl_class)
          @tasks[impl_class] = TaskProgress.new
        end
      end

      # Template method: Called when a task state is updated
      def on_task_updated(task_class, state, duration, error)
        return unless @enabled

        case state
        when :running
          @output.puts "[START] #{short_name(task_class)}"
        when :completed
          duration_str = duration ? " (#{format_duration(duration)})" : ""
          @output.puts "[DONE] #{short_name(task_class)}#{duration_str}"
        when :failed
          error_msg = error ? ": #{error.message}" : ""
          @output.puts "[FAIL] #{short_name(task_class)}#{error_msg}"
        when :cleaning
          @output.puts "[CLEAN] #{short_name(task_class)}"
        when :clean_completed
          duration_str = duration ? " (#{format_duration(duration)})" : ""
          @output.puts "[CLEAN DONE] #{short_name(task_class)}#{duration_str}"
        when :clean_failed
          error_msg = error ? ": #{error.message}" : ""
          @output.puts "[CLEAN FAIL] #{short_name(task_class)}#{error_msg}"
        end
        @output.flush
      end

      # Template method: Determine if display should activate
      def should_activate?
        @enabled
      end

      # Template method: Called when display starts
      def on_start
        return unless @enabled

        if @root_task_class
          @output.puts "[TASKI] Starting #{short_name(@root_task_class)}"
          @output.flush
        end
      end

      # Template method: Called when display stops
      def on_stop
        return unless @enabled

        total_duration = @start_time ? ((Time.now - @start_time) * 1000).to_i : 0
        completed = @tasks.values.count { |t| t.run_state == :completed }
        failed = @tasks.values.count { |t| t.run_state == :failed }
        total = @tasks.size

        if failed > 0
          @output.puts "[TASKI] Failed: #{failed}/#{total} tasks (#{total_duration}ms)"
        else
          @output.puts "[TASKI] Completed: #{completed}/#{total} tasks (#{total_duration}ms)"
        end
        @output.flush
      end
    end
  end
end
