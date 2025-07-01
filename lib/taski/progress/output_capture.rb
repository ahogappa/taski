# frozen_string_literal: true

module Taski
  module Progress
    # Captures stdout and maintains last N lines like tail -f
    class OutputCapture
      MAX_LINES = 10
      DISPLAY_LINES = 5

      def initialize(main_output)
        @main_output = main_output
        @buffer = []
        @capturing = false
        @original_stdout = nil
        @pipe_reader = nil
        @pipe_writer = nil
        @capture_thread = nil
      end

      def start
        return if @capturing

        @buffer.clear
        setup_stdout_redirection
        @capturing = true

        start_capture_thread
      end

      def stop
        return unless @capturing

        @capturing = false

        # Restore stdout
        restore_stdout

        # Clean up pipes and thread
        cleanup_capture_thread
        cleanup_pipes
      end

      def last_lines
        @buffer.last(DISPLAY_LINES)
      end

      def capturing?
        @capturing
      end

      private

      def setup_stdout_redirection
        @original_stdout = $stdout
        @pipe_reader, @pipe_writer = IO.pipe
        $stdout = @pipe_writer
      end

      def restore_stdout
        return unless @original_stdout

        $stdout = @original_stdout
        @original_stdout = nil
      end

      def start_capture_thread
        @capture_thread = Thread.new do
          while (line = @pipe_reader.gets)
            line = line.chomp
            next if line.empty?
            next if skip_line?(line)

            add_line_to_buffer(line)
          end
        rescue IOError
          # Pipe closed, normal termination
        end
      end

      def skip_line?(line)
        # Skip logger lines (they appear separately)
        line.match?(/^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3}\]/)
      end

      def add_line_to_buffer(line)
        @buffer << line
        @buffer.shift while @buffer.length > MAX_LINES
      end

      def cleanup_capture_thread
        @capture_thread&.join(0.1)
        @capture_thread = nil
      end

      def cleanup_pipes
        [@pipe_writer, @pipe_reader].each do |pipe|
          pipe&.close
        rescue IOError
          # Already closed, ignore
        end
        @pipe_writer = @pipe_reader = nil
      end
    end
  end
end
