# frozen_string_literal: true

require "monitor"
require_relative "task_output_pipe"

module Taski
  module Execution
    # Central coordinator that manages all task pipes and polling.
    # Also acts as an IO proxy for $stdout, routing writes to the appropriate pipe
    # based on the current thread.
    #
    # Architecture:
    # - Each task gets a dedicated IO pipe for output capture
    # - Writes are routed to the appropriate pipe based on Thread.current
    # - A reader thread polls all pipes using IO.select for efficiency
    # - When no pipe is registered for a thread, output goes to original stdout
    class TaskOutputRouter
      include MonitorMixin

      POLL_TIMEOUT = 0.05 # 50ms timeout for IO.select
      READ_BUFFER_SIZE = 4096

      def initialize(original_stdout)
        super()
        @original = original_stdout
        @pipes = {}       # task_class => TaskOutputPipe
        @thread_map = {}  # Thread => task_class
        @last_lines = {}  # task_class => String
      end

      # Start capturing output for the current thread
      # Creates a new pipe for the task and registers the thread mapping
      # @param task_class [Class] The task class being executed
      def start_capture(task_class)
        synchronize do
          pipe = TaskOutputPipe.new(task_class)
          @pipes[task_class] = pipe
          @thread_map[Thread.current] = task_class
        end
      end

      # Stop capturing output for the current thread
      # Closes the write end of the pipe
      def stop_capture
        synchronize do
          task_class = @thread_map.delete(Thread.current)
          return unless task_class

          pipe = @pipes[task_class]
          pipe&.close_write
        end
      end

      # Poll all open pipes for available data
      # Should be called periodically from the display thread
      def poll
        readable_pipes = synchronize do
          @pipes.values.reject { |p| p.read_closed? }.map(&:read_io)
        end
        return if readable_pipes.empty?

        ready, _, _ = IO.select(readable_pipes, nil, nil, POLL_TIMEOUT)
        return unless ready

        ready.each do |read_io|
          pipe = synchronize { @pipes.values.find { |p| p.read_io == read_io } }
          next unless pipe

          read_from_pipe(pipe)
        end
      end

      # Get the last output line for a task
      # @param task_class [Class] The task class
      # @return [String, nil] The last output line
      def last_line_for(task_class)
        synchronize { @last_lines[task_class] }
      end

      # Close all pipes and clean up
      def close_all
        synchronize do
          @pipes.each_value(&:close)
          @pipes.clear
          @thread_map.clear
        end
      end

      # Check if there are any active (not fully closed) pipes
      # @return [Boolean] true if there are active pipes
      def active?
        synchronize do
          @pipes.values.any? { |p| !p.read_closed? }
        end
      end

      # IO interface methods - route to pipe when capturing, otherwise pass through

      def write(str)
        pipe = current_thread_pipe
        if pipe && !pipe.write_closed?
          pipe.write_io.write(str)
        else
          @original.write(str)
        end
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

      # Get the write IO for the current thread's pipe
      # Used by Task#system to redirect subprocess output directly to the pipe
      # @return [IO, nil] The write IO or nil if not capturing
      def current_write_io
        synchronize do
          task_class = @thread_map[Thread.current]
          return nil unless task_class
          pipe = @pipes[task_class]
          return nil if pipe.nil? || pipe.write_closed?
          pipe.write_io
        end
      end

      # Delegate unknown methods to original stdout
      def method_missing(method, ...)
        @original.send(method, ...)
      end

      def respond_to_missing?(method, include_private = false)
        @original.respond_to?(method, include_private)
      end

      private

      def current_thread_pipe
        synchronize do
          task_class = @thread_map[Thread.current]
          return nil unless task_class
          @pipes[task_class]
        end
      end

      def read_from_pipe(pipe)
        data = pipe.read_io.read_nonblock(READ_BUFFER_SIZE)
        update_last_line(pipe.task_class, data)
      rescue IO::WaitReadable
        # No data available yet
      rescue EOFError
        # Pipe closed by writer, close read end
        synchronize { pipe.close_read }
      end

      def update_last_line(task_class, data)
        return if data.nil? || data.empty?

        lines = data.lines
        last_non_empty = lines.reverse.find { |l| !l.strip.empty? }
        synchronize do
          @last_lines[task_class] = last_non_empty&.strip if last_non_empty
        end
      end
    end
  end
end
