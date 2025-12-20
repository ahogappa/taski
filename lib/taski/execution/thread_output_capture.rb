# frozen_string_literal: true

require "monitor"
require "stringio"

module Taski
  module Execution
    # Thread-aware output capture wrapper for $stdout.
    # Captures output per-thread and suppresses it from stdout.
    # Output is only displayed inline next to tasks in the progress tree.
    class ThreadOutputCapture
      include MonitorMixin

      def initialize(original_stdout)
        super()
        @original = original_stdout
        @buffers = {}  # Thread -> StringIO
        @task_map = {} # Thread -> task_class
        @last_lines = {} # task_class -> last output line
      end

      # Start capturing output for the current thread
      # @param task_class [Class] The task class being executed
      def start_capture(task_class)
        synchronize do
          thread = Thread.current
          @buffers[thread] = StringIO.new
          @task_map[thread] = task_class
        end
      end

      # Stop capturing output for the current thread
      # @return [String, nil] The captured output
      def stop_capture
        synchronize do
          thread = Thread.current
          buffer = @buffers.delete(thread)
          task_class = @task_map.delete(thread)

          if buffer && task_class
            output = buffer.string
            last_line = extract_last_line(output)
            @last_lines[task_class] = last_line if last_line
            output
          end
        end
      end

      # Get the last output line for a task
      # @param task_class [Class] The task class
      # @return [String, nil] The last output line
      def last_line_for(task_class)
        synchronize { @last_lines[task_class] }
      end

      # IO interface methods - capture and suppress when capturing, otherwise pass through
      def write(str)
        is_capturing = false
        synchronize do
          thread = Thread.current
          if @buffers.key?(thread)
            is_capturing = true
            @buffers[thread].write(str)
            # Update last line in real-time
            task_class = @task_map[thread]
            if task_class
              current_output = @buffers[thread].string
              last_line = extract_last_line(current_output)
              @last_lines[task_class] = last_line if last_line
            end
          end
        end
        # Only write to original stdout when not capturing
        @original.write(str) unless is_capturing
      end

      def puts(*args)
        if args.empty?
          write("\n")
        else
          args.each do |arg|
            str = arg.to_s
            write(str)
            write("\n") unless str.end_with?("\n")
          end
        end
        nil
      end

      def print(*args)
        args.each { |arg| write(arg.to_s) }
        nil
      end

      def <<(str)
        write(str.to_s)
        self
      end

      def flush
        @original.flush
      end

      def tty?
        @original.tty?
      end

      def isatty
        @original.isatty
      end

      def winsize
        @original.winsize
      end

      # Delegate unknown methods to original stdout
      def method_missing(method, ...)
        @original.send(method, ...)
      end

      def respond_to_missing?(method, include_private = false)
        @original.respond_to?(method, include_private)
      end

      private

      # Extract the last non-empty line from output
      def extract_last_line(output)
        return nil if output.nil? || output.empty?

        lines = output.lines
        # Find last non-empty line
        lines.reverse_each do |line|
          stripped = line.chomp.strip
          return stripped unless stripped.empty?
        end
        nil
      end
    end
  end
end
