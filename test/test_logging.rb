# frozen_string_literal: true

require_relative "test_helper"
require "logger"
require "json"

class TestLogging < Minitest::Test
  def setup
    @log_output = StringIO.new
    @original_logger = Taski.logger
    Taski.reset_progress_display!
    Taski.progress_display = Taski::Progress::Layout::Log.new
    Taski::Task.reset!
  end

  def teardown
    Taski.logger = @original_logger
    Taski.reset_progress_display!
  end

  def test_logger_is_nil_by_default
    Taski.logger = nil
    assert_nil Taski.logger
  end

  def test_logger_can_be_set
    logger = Logger.new(@log_output)
    Taski.logger = logger
    assert_equal logger, Taski.logger
  end

  def test_logging_is_noop_when_logger_is_nil
    Taski.logger = nil
    run_simple_task
    assert_equal "", @log_output.string
  end

  def test_execution_started_event_is_logged
    set_logger(level: Logger::INFO)
    run_simple_task

    started_event = find_event("execution.started")

    refute_nil started_event, "execution.started event should be logged"
    assert started_event["data"]["worker_count"] > 0
  end

  def test_execution_completed_event_is_logged
    set_logger(level: Logger::INFO)
    run_simple_task

    completed_event = find_event("execution.completed")

    refute_nil completed_event, "execution.completed event should be logged"
    assert completed_event["data"]["duration_ms"] >= 0
    assert_equal 1, completed_event["data"]["task_count"]
  end

  def test_task_started_event_is_logged
    set_logger(level: Logger::INFO)
    run_simple_task

    started_event = find_event("task.started")

    refute_nil started_event, "task.started event should be logged"
    refute_nil started_event["thread_id"]
  end

  def test_task_completed_event_is_logged
    set_logger(level: Logger::INFO)
    run_simple_task

    completed_event = find_event("task.completed")

    refute_nil completed_event, "task.completed event should be logged"
    assert completed_event["data"]["duration_ms"] >= 0
  end

  def test_task_failed_event_is_logged
    set_logger(level: Logger::ERROR)

    failing_task = Class.new(Taski::Task) do
      def run
        raise "intentional error"
      end
    end

    assert_raises(Taski::AggregateError) { failing_task.run }

    refute_nil find_event("task.failed"), "task.failed event should be logged"
  end

  def test_clean_events_are_logged_at_debug_level
    set_logger(level: Logger::DEBUG)

    task_with_clean = Class.new(Taski::Task) do
      def run = "result"
      def clean = "cleaned"
    end

    task_with_clean.run_and_clean

    refute_nil find_event("task.clean_started"), "task.clean_started event should be logged"
    refute_nil find_event("task.clean_completed"), "task.clean_completed event should be logged"
  end

  def test_log_entry_format_is_json
    set_logger(level: Logger::INFO)
    run_simple_task

    log_lines = @log_output.string.lines.map(&:strip).reject(&:empty?)
    log_lines.each do |line|
      json_part = extract_json_from_log_line(line)
      refute_nil json_part, "Each log line should contain valid JSON"

      parsed = JSON.parse(json_part)
      assert parsed.key?("timestamp"), "Log entry should have timestamp"
      assert parsed.key?("event"), "Log entry should have event"
      assert parsed.key?("thread_id"), "Log entry should have thread_id"
    end
  end

  def test_error_detail_logged_via_logging_module
    set_logger(level: Logger::ERROR)
    @log_output.truncate(0)
    @log_output.rewind

    task_class = Class.new(Taski::Task)
    task_class.define_singleton_method(:name) { "FailingTask" }

    error = RuntimeError.new("something broke")
    error.set_backtrace(["file.rb:10:in `run'", "file.rb:20:in `execute'"])

    Taski::Logging.error(
      Taski::Logging::Events::TASK_ERROR_DETAIL,
      task: task_class.name,
      error_class: error.class.name,
      error_message: error.message,
      backtrace: error.backtrace&.first(10)
    )

    error_event = find_event("task.error_detail")

    refute_nil error_event, "task.error_detail event should be logged"
    assert_equal "FailingTask", error_event["task"]
    assert_equal "RuntimeError", error_event["data"]["error_class"]
    assert_equal "something broke", error_event["data"]["error_message"]
  end

  def test_thread_safety_of_logger_access
    Taski.logger = nil

    threads = 10.times.map do |i|
      Thread.new do
        if i.even?
          Taski.logger = Logger.new(StringIO.new)
        else
          Taski.logger
        end
      end
    end

    threads.each(&:value)
  end

  private

  def set_logger(level:)
    Taski.logger = Logger.new(@log_output, level: level)
  end

  def run_simple_task
    task = Class.new(Taski::Task) { def run = "result" }
    task.run
  end

  def find_event(event_name)
    parse_log_lines(@log_output.string).find { |e| e["event"] == event_name }
  end

  def parse_log_lines(log_output)
    log_output.lines.filter_map do |line|
      json_part = extract_json_from_log_line(line)
      JSON.parse(json_part) if json_part
    end
  end

  def extract_json_from_log_line(line)
    line.match(/\{.*\}/)&.[](0)
  end
end
