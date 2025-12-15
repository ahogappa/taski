# frozen_string_literal: true

require "monitor"

module Taski
  module Execution
    class ParallelProgressDisplay
      SPINNER_FRAMES = %w[⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏].freeze

      class TaskProgress
        attr_accessor :state, :start_time, :end_time, :error, :duration

        def initialize
          @state = :pending
          @start_time = nil
          @end_time = nil
          @error = nil
          @duration = nil
        end
      end

      def initialize(output: $stdout)
        @output = output
        @tasks = {}
        @monitor = Monitor.new
        @spinner_index = 0
        @renderer_thread = nil
        @running = false
      end

      # @param task_class [Class] The task class to register
      def register_task(task_class)
        @monitor.synchronize do
          @tasks[task_class] = TaskProgress.new
        end
      end

      # @param task_class [Class] The task class to check
      # @return [Boolean] true if the task is registered
      def task_registered?(task_class)
        @monitor.synchronize do
          @tasks.key?(task_class)
        end
      end

      # @param task_class [Class] The task class to update
      # @param state [Symbol] The new state (:pending, :running, :completed, :failed)
      # @param duration [Float] Duration in milliseconds (for completed tasks)
      # @param error [Exception] Error object (for failed tasks)
      def update_task(task_class, state:, duration: nil, error: nil)
        @monitor.synchronize do
          progress = @tasks[task_class]
          return unless progress

          progress.state = state
          progress.duration = duration if duration
          progress.error = error if error

          case state
          when :running
            progress.start_time = Time.now
          when :completed, :failed
            progress.end_time = Time.now
          end
        end
      end

      # @param task_class [Class] The task class
      # @return [Symbol] The task state
      def task_state(task_class)
        @monitor.synchronize do
          @tasks[task_class]&.state
        end
      end

      def render
        @monitor.synchronize do
          @tasks.each do |task_class, progress|
            line = format_task_line(task_class, progress)
            @output.puts line
          end
        end
      end

      def start
        return if @running

        @running = true
        @renderer_thread = Thread.new do
          loop do
            break unless @running
            render_live
            sleep 0.1
          end
        end
      end

      def stop
        return unless @running

        @running = false
        @renderer_thread&.join
        render_final
      end

      private

      # @return [Array<String>] Array of formatted task lines
      def collect_task_lines
        @tasks.map do |task_class, progress|
          format_task_line(task_class, progress)
        end
      end

      def render_live
        return unless @output.tty?

        @monitor.synchronize do
          @spinner_index += 1

          lines = collect_task_lines

          lines.each_with_index do |line, index|
            @output.print "\r\e[K#{line}"
            @output.print "\n" unless index == lines.length - 1
          end

          @output.print "\e[#{lines.length - 1}A" if lines.length > 1
        end
      end

      def render_final
        @monitor.synchronize do
          lines = collect_task_lines

          if @output.tty? && lines.length > 0
            lines.each_with_index do |_, index|
              @output.print "\r\e[K"
              @output.print "\e[1B" unless index == lines.length - 1
            end
            @output.print "\e[#{lines.length - 1}A" if lines.length > 1
          end

          lines.each do |line|
            @output.puts line
          end
        end
      end

      # @param task_class [Class] The task class
      # @param progress [TaskProgress] The task progress
      # @return [String] Formatted line
      def format_task_line(task_class, progress)
        icon = task_icon(progress.state)
        name = task_class.name || "AnonymousTask"
        details = task_details(progress)

        "#{icon} #{name}#{details}"
      end

      # @param state [Symbol] The task state
      # @return [String] The icon character
      def task_icon(state)
        case state
        when :completed
          "✅"
        when :failed
          "❌"
        when :running
          spinner_char
        when :pending
          "⏳"
        else
          "❓"
        end
      end

      # @return [String] Current spinner frame
      def spinner_char
        SPINNER_FRAMES[@spinner_index % SPINNER_FRAMES.length]
      end

      # @param progress [TaskProgress] The task progress
      # @return [String] Details string
      def task_details(progress)
        case progress.state
        when :completed
          " (#{progress.duration}ms)"
        when :failed
          " (failed)"
        when :running
          " (running)"
        when :pending
          " (pending)"
        else
          ""
        end
      end
    end
  end
end
