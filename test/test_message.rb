# frozen_string_literal: true

require "test_helper"
require "stringio"

class TestMessage < Minitest::Test
  def setup
    Taski::Task.reset! if defined?(Taski::Task)
    Taski.reset_progress_display!
    # Clear any thread-local context
    Taski::Execution::ExecutionContext.current = nil
  end

  def teardown
    Taski.reset_progress_display!
    Taski::Execution::ExecutionContext.current = nil
  end

  # ========================================
  # Unit Tests for ExecutionContext message queue
  # ========================================

  def test_queue_message_adds_to_queue
    context = Taski::Execution::ExecutionContext.new

    context.queue_message("Message 1")
    context.queue_message("Message 2")

    output = StringIO.new
    context.flush_messages(output)

    assert_equal "Message 1\nMessage 2\n", output.string
  end

  def test_flush_messages_clears_queue
    context = Taski::Execution::ExecutionContext.new

    context.queue_message("Test message")

    output1 = StringIO.new
    context.flush_messages(output1)
    assert_equal "Test message\n", output1.string

    output2 = StringIO.new
    context.flush_messages(output2)
    assert_equal "", output2.string, "Queue should be empty after flush"
  end

  def test_flush_messages_with_empty_queue
    context = Taski::Execution::ExecutionContext.new
    output = StringIO.new

    context.flush_messages(output)

    assert_equal "", output.string
  end

  def test_original_stdout_accessor
    context = Taski::Execution::ExecutionContext.new
    mock_io = StringIO.new

    assert_nil context.original_stdout, "Should be nil before setup"

    original_stdout = $stdout
    begin
      context.setup_output_capture(mock_io)
      assert_equal mock_io, context.original_stdout, "Should return original stdout after setup"

      context.teardown_output_capture
      assert_nil context.original_stdout, "Should be nil after teardown"
    ensure
      $stdout = original_stdout
    end
  end

  # ========================================
  # Taski.message behavior tests
  # ========================================

  def test_message_without_active_context_outputs_immediately
    output = StringIO.new
    original_stdout = $stdout

    begin
      $stdout = output
      Taski.message("Direct output")
    ensure
      $stdout = original_stdout
    end

    assert_equal "Direct output\n", output.string
  end

  def test_message_with_inactive_capture_outputs_immediately
    context = Taski::Execution::ExecutionContext.new
    Taski::Execution::ExecutionContext.current = context

    output = StringIO.new
    original_stdout = $stdout

    begin
      $stdout = output
      refute context.output_capture_active?, "Capture should be inactive"
      Taski.message("Direct output")
    ensure
      $stdout = original_stdout
    end

    assert_equal "Direct output\n", output.string
  end

  def test_message_with_active_capture_queues_message
    context = Taski::Execution::ExecutionContext.new
    Taski::Execution::ExecutionContext.current = context
    mock_io = StringIO.new

    original_stdout = $stdout
    begin
      context.setup_output_capture(mock_io)

      # Message should be queued, not written immediately
      Taski.message("Queued message")

      # The mock_io should not contain the message yet
      refute_includes mock_io.string, "Queued message"

      # Flush should output the message
      output = StringIO.new
      context.flush_messages(output)
      assert_equal "Queued message\n", output.string
    ensure
      context.teardown_output_capture
      $stdout = original_stdout
    end
  end

  def test_message_thread_safety
    context = Taski::Execution::ExecutionContext.new
    Taski::Execution::ExecutionContext.current = context
    mock_io = StringIO.new

    original_stdout = $stdout
    begin
      context.setup_output_capture(mock_io)

      threads = 10.times.map do |i|
        Thread.new do
          10.times do |j|
            # Set context in each thread
            Taski::Execution::ExecutionContext.current = context
            Taski.message("Thread #{i} message #{j}")
          end
        end
      end

      threads.each(&:join)

      output = StringIO.new
      context.flush_messages(output)

      lines = output.string.lines
      assert_equal 100, lines.size, "Should have 100 messages"
    ensure
      context.teardown_output_capture
      $stdout = original_stdout
    end
  end

  # ========================================
  # Integration test with actual task execution
  # ========================================

  def test_message_in_task_execution
    original_stdout = $stdout

    # Use PlainProgressDisplay for easier testing
    ENV["TASKI_PROGRESS_MODE"] = "plain"

    task_class = Class.new(Taski::Task) do
      exports :result

      def run
        Taski.message("Created: /path/to/output.txt")
        Taski.message("Summary: 42 items processed")
        @result = "done"
      end
    end

    output = StringIO.new
    begin
      $stdout = output
      $stderr = output

      task_class.run
    ensure
      $stdout = original_stdout
      $stderr = STDERR
      ENV.delete("TASKI_PROGRESS_MODE")
    end

    # Messages should appear after task completion
    assert_includes output.string, "Created: /path/to/output.txt"
    assert_includes output.string, "Summary: 42 items processed"
  end

  def test_message_order_preserved
    context = Taski::Execution::ExecutionContext.new
    Taski::Execution::ExecutionContext.current = context
    mock_io = StringIO.new

    original_stdout = $stdout
    begin
      context.setup_output_capture(mock_io)

      Taski.message("First")
      Taski.message("Second")
      Taski.message("Third")

      output = StringIO.new
      context.flush_messages(output)

      lines = output.string.lines.map(&:chomp)
      assert_equal %w[First Second Third], lines
    ensure
      context.teardown_output_capture
      $stdout = original_stdout
    end
  end
end
