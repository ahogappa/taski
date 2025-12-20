# frozen_string_literal: true

module Taski
  module Execution
    # Manages a single IO pipe for capturing task output
    # Each task gets its own dedicated pipe for stdout capture
    class TaskOutputPipe
      attr_reader :read_io, :write_io, :task_class

      def initialize(task_class)
        @task_class = task_class
        @read_io, @write_io = IO.pipe
        @write_io.sync = true
      end

      def close_write
        @write_io.close unless @write_io.closed?
      end

      def close_read
        @read_io.close unless @read_io.closed?
      end

      def close
        close_write
        close_read
      end

      def write_closed?
        @write_io.closed?
      end

      def read_closed?
        @read_io.closed?
      end

      def closed?
        write_closed? && read_closed?
      end
    end
  end
end
