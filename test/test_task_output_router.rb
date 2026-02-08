# frozen_string_literal: true

require "test_helper"
require "logger"

class TestTaskOutputRouter < Minitest::Test
  def setup
    @original_stdout = StringIO.new
    @router = Taski::Execution::TaskOutputRouter.new(@original_stdout)
  end

  def teardown
    @router.close_all
  end

  # Errno::EBADF occurs when IO.select is blocked and another thread closes the IO.
  # This simulates the race condition between the poll thread and stop_capture/drain_pipe.
  def test_poll_handles_ebadf_when_pipe_closed_during_io_select
    task_class = Class.new(Taski::Task)

    @router.start_capture(task_class)

    pipe = @router.instance_variable_get(:@pipes)[task_class]

    # Close the pipe from another thread while poll is blocked on IO.select
    closer = Thread.new do
      sleep 0.01
      pipe.close_read
    end

    # poll should not raise Errno::EBADF
    @router.poll

    closer.join
  end

  # ========================================
  # read API
  # ========================================

  def test_read_returns_all_lines
    task_class = Class.new(Taski::Task)

    @router.start_capture(task_class)

    thread = Thread.new do
      @router.send(:store_output_lines, task_class, "line1\nline2\nline3\n")
    end
    thread.join

    result = @router.read(task_class)
    assert_equal ["line1", "line2", "line3"], result
  end

  def test_read_with_limit
    task_class = Class.new(Taski::Task)

    @router.start_capture(task_class)

    @router.send(:store_output_lines, task_class, (1..10).map { |i| "line#{i}" }.join("\n") + "\n")

    result = @router.read(task_class, limit: 5)
    assert_equal ["line6", "line7", "line8", "line9", "line10"], result
  end

  def test_read_returns_empty_for_unknown_task
    task_class = Class.new(Taski::Task)

    result = @router.read(task_class)
    assert_equal [], result
  end

  # ========================================
  # output logging
  # ========================================

  def test_store_output_lines_logs_to_debug
    task_class = Class.new(Taski::Task)
    task_class.define_singleton_method(:name) { "LoggedTask" }

    log_output = StringIO.new
    logger = Logger.new(log_output)
    logger.level = Logger::DEBUG
    logger.formatter = proc { |_severity, _datetime, _progname, msg| "#{msg}\n" }

    original_logger = Taski.logger
    begin
      Taski.logger = logger

      @router.start_capture(task_class)
      @router.send(:store_output_lines, task_class, "hello world\n")

      log_content = log_output.string
      assert_includes log_content, "task.output"
      assert_includes log_content, "LoggedTask"
      assert_includes log_content, "hello world"
    ensure
      Taski.logger = original_logger
    end
  end

  # ========================================
  # stderr capture
  # ========================================

  def test_stderr_capture_routes_to_pipe
    task_class = Class.new(Taski::Task)

    @router.start_capture(task_class)

    # Simulate stderr write on a captured thread
    thread = Thread.new do
      # Register thread for this task
      @router.send(:synchronize) do
        @router.instance_variable_get(:@thread_map)[Thread.current] = task_class
      end
      # Write via the router (as $stderr would do)
      @router.puts("stderr output")
      @router.stop_capture
    end
    thread.join

    # Drain and verify
    @router.poll
    sleep 0.05
    lines = @router.read(task_class)
    assert_includes lines, "stderr output"
  end

  def test_read_returns_independent_copy
    task_class = Class.new(Taski::Task)

    @router.start_capture(task_class)
    @router.send(:store_output_lines, task_class, "line1\n")

    result1 = @router.read(task_class)
    result1 << "modified"

    result2 = @router.read(task_class)
    assert_equal ["line1"], result2
  end

  # Same race condition in drain_pipe (via stop_capture): IO.select blocked while another thread closes the IO
  def test_stop_capture_handles_ebadf_when_pipe_closed_during_drain
    task_class = Class.new(Taski::Task)

    @router.start_capture(task_class)

    pipe = @router.instance_variable_get(:@pipes)[task_class]

    # Close the read end from another thread while drain_pipe is blocked on IO.select
    closer = Thread.new do
      sleep 0.01
      pipe.read_io.close
    end

    # stop_capture (which calls drain_pipe internally) should not raise Errno::EBADF
    @router.stop_capture

    closer.join
  end

  # Same race condition in read_from_pipe via poll
  def test_read_from_pipe_handles_ebadf_when_pipe_closed_during_read
    task_class = Class.new(Taski::Task)

    @router.start_capture(task_class)

    pipe = @router.instance_variable_get(:@pipes)[task_class]

    # Close the read IO from another thread while read_from_pipe tries to read
    closer = Thread.new do
      sleep 0.005
      pipe.read_io.close
    end

    # read_from_pipe should not raise Errno::EBADF
    @router.send(:read_from_pipe, pipe)

    closer.join
  end
end
