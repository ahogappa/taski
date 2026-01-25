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
  # Unit Tests for BaseProgressDisplay message queue
  # ========================================

  def test_progress_display_queue_message
    display = Taski::Execution::SimpleProgressDisplay.new

    display.queue_message("Message 1")
    display.queue_message("Message 2")

    # Messages should be queued (not yet flushed)
    # They will be flushed when stop is called with nest_level reaching 0
  end

  # ========================================
  # Taski.message behavior tests
  # ========================================

  def test_message_without_progress_display_outputs_immediately
    Taski.reset_progress_display!
    ENV["TASKI_PROGRESS_DISABLE"] = "1"

    output = StringIO.new
    original_stdout = $stdout

    begin
      $stdout = output
      Taski.message("Direct output")
    ensure
      $stdout = original_stdout
      ENV.delete("TASKI_PROGRESS_DISABLE")
    end

    assert_equal "Direct output\n", output.string
  end

  def test_message_with_progress_display_queues_message
    output = StringIO.new
    display = Taski::Execution::SimpleProgressDisplay.new(output: output)

    # Manually set the progress display
    Taski.instance_variable_set(:@progress_display, display)

    # Simulate start (nest_level becomes 1)
    display.start

    # Queue a message
    Taski.message("Queued message")

    # Message should not be in output yet
    refute_includes output.string, "Queued message"

    # Stop should flush messages
    display.stop

    assert_includes output.string, "Queued message"
  ensure
    Taski.reset_progress_display!
  end

  def test_message_thread_safety
    output = StringIO.new
    display = Taski::Execution::SimpleProgressDisplay.new(output: output)

    Taski.instance_variable_set(:@progress_display, display)
    display.start

    threads = 10.times.map do |i|
      Thread.new do
        10.times do |j|
          Taski.message("Thread #{i} message #{j}")
        end
      end
    end

    threads.each(&:join)

    display.stop

    lines = output.string.lines.select { |l| l.include?("Thread") }
    assert_equal 100, lines.size, "Should have 100 messages"
  ensure
    Taski.reset_progress_display!
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
    output = StringIO.new
    display = Taski::Execution::SimpleProgressDisplay.new(output: output)

    Taski.instance_variable_set(:@progress_display, display)
    display.start

    Taski.message("First")
    Taski.message("Second")
    Taski.message("Third")

    display.stop

    lines = output.string.lines.select { |l| l.match?(/^(First|Second|Third)$/) }.map(&:chomp)
    assert_equal %w[First Second Third], lines
  ensure
    Taski.reset_progress_display!
  end

  # ========================================
  # Nested executor tests
  # ========================================

  def test_message_flushed_only_when_all_executors_stop
    output = StringIO.new
    display = Taski::Execution::SimpleProgressDisplay.new(output: output)

    Taski.instance_variable_set(:@progress_display, display)

    # Simulate outer executor start
    display.start
    # Simulate inner executor start
    display.start

    Taski.message("Nested message")

    # Inner executor stop - message should NOT be flushed yet
    display.stop
    refute_includes output.string, "Nested message", "Message should not be flushed when inner executor stops"

    # Outer executor stop - message SHOULD be flushed now
    display.stop
    assert_includes output.string, "Nested message", "Message should be flushed when outer executor stops"
  ensure
    Taski.reset_progress_display!
  end
end
