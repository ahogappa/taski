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
      POLL_INTERVAL = 0.1 # 100ms between polls (matches TreeProgressDisplay)
      READ_BUFFER_SIZE = 4096
      MAX_RECENT_LINES = 30 # Maximum number of recent lines to keep per task

      def initialize(original_stdout, execution_context = nil)
        super()
        @original = original_stdout
        @execution_context = execution_context
        @pipes = {}         # task_class => TaskOutputPipe
        @thread_map = {}    # Thread => task_class
        @recent_lines = {}  # task_class => Array<String>
        @poll_thread = nil
        @polling = false
      end

      # Start the background polling thread
      # This ensures pipes are drained even when display doesn't poll
      def start_polling
        synchronize do
          return if @polling
          @polling = true
        end

        @poll_thread = Thread.new do
          loop do
            break unless @polling
            poll
            sleep POLL_INTERVAL
          end
        end
      end

      def stop_polling
        synchronize { @polling = false }
        @poll_thread&.join(0.5)
        @poll_thread = nil
      end

      def start_capture(task_class)
        synchronize do
          pipe = TaskOutputPipe.new(task_class)
          @pipes[task_class] = pipe
          @thread_map[Thread.current] = task_class
          Taski::Logging.debug(Taski::Logging::Events::OUTPUT_ROUTER_START_CAPTURE, task: task_class.name)
        end
      end

      # Closes the write end and drains remaining data.
      def stop_capture
        task_class = nil
        pipe = nil

        synchronize do
          task_class = @thread_map.delete(Thread.current)
          unless task_class
            Taski::Logging.debug(Taski::Logging::Events::OUTPUT_ROUTER_STOP_CAPTURE_UNREGISTERED)
            return
          end

          pipe = @pipes[task_class]
          pipe&.close_write
          Taski::Logging.debug(Taski::Logging::Events::OUTPUT_ROUTER_STOP_CAPTURE, task: task_class.name)
        end

        # Drain any remaining data from the pipe after closing write end
        drain_pipe(pipe) if pipe
      end

      # Called periodically from the display thread.
      def poll
        readable_pipes = synchronize do
          @pipes.values.reject { |p| p.read_closed? }.map(&:read_io)
        end
        return if readable_pipes.empty?

        # Handle race condition: pipe may be closed between check and select
        ready, = IO.select(readable_pipes, nil, nil, POLL_TIMEOUT)
        return unless ready

        ready.each do |read_io|
          pipe = synchronize { @pipes.values.find { |p| p.read_io == read_io } }
          next unless pipe

          read_from_pipe(pipe)
        end
      rescue IOError, Errno::EBADF
        # Pipe was closed by another thread (drain_pipe), ignore
      end

      def last_line_for(task_class)
        synchronize { @recent_lines[task_class]&.last }
      end

      def read(task_class, limit: nil)
        synchronize do
          lines = (@recent_lines[task_class] || []).dup
          limit ? lines.last(limit) : lines
        end
      end

      def close_all
        synchronize do
          @pipes.each_value(&:close)
          @pipes.clear
          @thread_map.clear
        end
      end

      def active?
        synchronize do
          @pipes.values.any? { |p| !p.read_closed? }
        end
      end

      # IO interface methods - route to pipe when capturing, otherwise pass through

      def write(str)
        pipe = current_thread_pipe
        if pipe && !pipe.write_closed?
          begin
            pipe.write_io.write(str)
          rescue IOError
            # Pipe was closed by another thread (e.g., stop_capture), fall back to original
            @original.write(str)
          end
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

      # Used by Task#system to redirect subprocess output to the pipe.
      def current_write_io
        synchronize do
          task_class = @thread_map[Thread.current]
          return nil unless task_class
          pipe = @pipes[task_class]
          return nil if pipe.nil? || pipe.write_closed?
          pipe.write_io
        end
      end

      def method_missing(method, ...)
        @original.send(method, ...)
      end

      def respond_to_missing?(method, include_private = false)
        @original.respond_to?(method, include_private)
      end

      private

      def drain_pipe(pipe)
        return if pipe.read_closed?

        loop do
          data = pipe.read_io.read_nonblock(READ_BUFFER_SIZE)
          Taski::Logging.debug(Taski::Logging::Events::OUTPUT_ROUTER_DRAIN_PIPE, task: pipe.task_class.name, bytes: data.bytesize)
          store_output_lines(pipe.task_class, data)
        rescue IO::WaitReadable
          # Check if there's more data with a very short timeout
          ready, = IO.select([pipe.read_io], nil, nil, 0.001)
          break unless ready
        rescue IOError, Errno::EBADF
          # All data has been read (EOFError) or pipe was closed by another thread
          synchronize { pipe.close_read }
          break
        end
      end

      def current_thread_pipe
        synchronize do
          task_class = @thread_map[Thread.current]
          return nil unless task_class
          @pipes[task_class]
        end
      end

      def read_from_pipe(pipe)
        data = pipe.read_io.read_nonblock(READ_BUFFER_SIZE)
        store_output_lines(pipe.task_class, data)
      rescue IO::WaitReadable
        # No data available yet
      rescue IOError, Errno::EBADF
        # Pipe closed by writer (EOFError) or by another thread, close read end
        synchronize { pipe.close_read }
      end

      def store_output_lines(task_class, data)
        return if data.nil? || data.empty?

        lines = data.lines
        synchronize do
          @recent_lines[task_class] ||= []
          lines.each do |line|
            stripped = line.chomp
            next if stripped.strip.empty?
            @recent_lines[task_class] << stripped
            Taski::Logging.debug(
              Taski::Logging::Events::TASK_OUTPUT,
              task: task_class.name,
              line: stripped
            )
          end
          if @recent_lines[task_class].size > MAX_RECENT_LINES
            @recent_lines[task_class] = @recent_lines[task_class].last(MAX_RECENT_LINES)
          end
          Taski::Logging.debug(Taski::Logging::Events::OUTPUT_ROUTER_STORE_LINES, task: task_class.name, line_count: @recent_lines[task_class].size)
        end
      end
    end
  end
end
