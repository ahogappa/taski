# frozen_string_literal: true

require "test_helper"

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

  # Same race condition in drain_pipe: IO.select blocked while another thread closes the IO
  def test_drain_pipe_handles_ebadf_when_pipe_closed_during_io_select
    task_class = Class.new(Taski::Task)

    @router.start_capture(task_class)

    pipe = @router.instance_variable_get(:@pipes)[task_class]
    pipe.close_write

    # Close the read end from another thread while drain_pipe is blocked on IO.select
    closer = Thread.new do
      sleep 0.01
      pipe.read_io.close
    end

    # drain_pipe should not raise Errno::EBADF
    @router.drain_pipe(pipe)

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
