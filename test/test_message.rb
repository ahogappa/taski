# frozen_string_literal: true

require "test_helper"
require "stringio"

class TestMessage < Minitest::Test
  def setup
    Taski::Task.reset! if defined?(Taski::Task)
    Taski.reset_progress_display!
    # Clear any thread-local context
    Taski::Execution::ExecutionContext.current = nil
    # Ensure progress is not disabled from other tests
    ENV.delete("TASKI_PROGRESS_DISABLE")
    ENV.delete("TASKI_PROGRESS_MODE")
  end

  def teardown
    Taski.reset_progress_display!
    Taski::Execution::ExecutionContext.current = nil
    ENV.delete("TASKI_PROGRESS_DISABLE")
    ENV.delete("TASKI_PROGRESS_MODE")
  end

  # ========================================
  # Unit Tests for BaseProgressDisplay message queue
  # ========================================

  def test_progress_display_queue_message_directly
    output = StringIO.new
    display = Taski::Execution::Layout::Simple.new(output: output)

    # Queue messages directly to the display
    display.queue_message("Message 1")
    display.queue_message("Message 2")

    # Start and stop to trigger flush
    display.start
    display.stop

    assert_includes output.string, "Message 1"
    assert_includes output.string, "Message 2"
  end

  def test_progress_display_flush_on_stop
    output = StringIO.new
    display = Taski::Execution::Layout::Simple.new(output: output)

    display.start
    display.queue_message("Test message")

    # Before stop, message should not be in output
    refute_includes output.string, "Test message"

    display.stop

    # After stop, message should be flushed
    assert_includes output.string, "Test message"
  end

  # ========================================
  # Taski.message behavior tests
  # ========================================

  def test_message_without_progress_display_outputs_immediately
    ENV["TASKI_PROGRESS_DISABLE"] = "1"
    Taski.reset_progress_display!

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

  # ========================================
  # Integration tests with actual task execution
  # ========================================

  def test_message_in_task_execution_with_plain_mode
    original_stdout = $stdout

    ENV["TASKI_PROGRESS_MODE"] = "plain"
    Taski.reset_progress_display!

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
    end

    # Messages should appear after task completion
    assert_includes output.string, "Created: /path/to/output.txt"
    assert_includes output.string, "Summary: 42 items processed"
  end

  def test_message_order_preserved_direct
    output = StringIO.new
    display = Taski::Execution::Layout::Simple.new(output: output)

    display.start
    display.queue_message("First")
    display.queue_message("Second")
    display.queue_message("Third")
    display.stop

    lines = output.string.lines.select { |l| l.match?(/^(First|Second|Third)$/) }.map(&:chomp)
    assert_equal %w[First Second Third], lines
  end

  def test_message_thread_safety_direct
    output = StringIO.new
    display = Taski::Execution::Layout::Simple.new(output: output)

    display.start

    threads = 10.times.map do |i|
      Thread.new do
        10.times do |j|
          display.queue_message("Thread #{i} message #{j}")
        end
      end
    end

    threads.each(&:join)

    display.stop

    lines = output.string.lines.select { |l| l.include?("Thread") }
    assert_equal 100, lines.size, "Should have 100 messages"
  end

  # ========================================
  # Nested executor tests
  # ========================================

  def test_message_flushed_only_when_nest_level_zero
    output = StringIO.new
    display = Taski::Execution::Layout::Simple.new(output: output)

    # Simulate outer executor start
    display.start
    # Simulate inner executor start
    display.start

    display.queue_message("Nested message")

    # Inner executor stop - message should NOT be flushed yet (nest_level still > 0)
    display.stop
    refute_includes output.string, "Nested message", "Message should not be flushed when inner executor stops"

    # Outer executor stop - message SHOULD be flushed now (nest_level = 0)
    display.stop
    assert_includes output.string, "Nested message", "Message should be flushed when outer executor stops"
  end
end
