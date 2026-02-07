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

    # Close all pipes from another thread while poll is blocked on IO.select
    closer = Thread.new do
      sleep 0.01
      @router.close_all
    end

    # poll should not raise Errno::EBADF
    @router.poll

    closer.join
  end

  # Same race condition in drain_pipe: IO.select blocked while another thread closes the IO.
  # stop_capture calls drain_pipe internally, and close_all closes the pipe concurrently.
  def test_stop_capture_handles_ebadf_when_pipe_closed_during_drain
    task_class = Class.new(Taski::Task)

    @router.start_capture(task_class)

    # Close all pipes from another thread while stop_capture is draining
    closer = Thread.new do
      sleep 0.01
      @router.close_all
    end

    # stop_capture internally calls drain_pipe, should not raise Errno::EBADF
    @router.stop_capture

    closer.join
  end
end
