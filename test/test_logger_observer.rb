# frozen_string_literal: true

require "test_helper"
require "logger"
require "stringio"

class TestLoggerObserver < Minitest::Test
  def setup
    @log_output = StringIO.new
    @original_logger = Taski.logger
    Taski.logger = Logger.new(@log_output, level: Logger::DEBUG)
  end

  def teardown
    Taski.logger = @original_logger
  end

  def test_on_ready_logs_execution_ready_with_task_count
    observer = Taski::Logging::LoggerObserver.new
    context = Taski::Execution::ExecutionContext.new

    # Create a mock dependency graph with 3 tasks
    mock_graph = Object.new
    mock_graph.define_singleton_method(:all_tasks) { [Class.new, Class.new, Class.new] }

    context.dependency_graph = mock_graph
    context.add_observer(observer)

    observer.on_ready

    log_content = @log_output.string
    assert_match(/execution\.ready/, log_content)
    assert_match(/"total_tasks":3/, log_content)
  end

  def test_on_ready_works_without_dependency_graph
    observer = Taski::Logging::LoggerObserver.new
    context = Taski::Execution::ExecutionContext.new

    context.add_observer(observer)

    # Should not raise even without dependency_graph
    observer.on_ready

    log_content = @log_output.string
    assert_match(/execution\.ready/, log_content)
  end

  def test_on_task_updated_logs_run_phase_transitions
    observer = Taski::Logging::LoggerObserver.new
    context = Taski::Execution::ExecutionContext.new
    context.current_phase = :run
    context.add_observer(observer)

    task_class = Class.new
    task_class.define_singleton_method(:name) { "TestTask" }

    # Test pending -> running
    timestamp = Time.now
    observer.on_task_updated(task_class, previous_state: :pending, current_state: :running, timestamp: timestamp)

    log_content = @log_output.string
    assert_match(/task\.started/, log_content)
    assert_match(/TestTask/, log_content)
  end

  def test_on_task_updated_logs_skipped_state
    observer = Taski::Logging::LoggerObserver.new
    context = Taski::Execution::ExecutionContext.new
    context.current_phase = :run
    context.add_observer(observer)

    task_class = Class.new
    task_class.define_singleton_method(:name) { "SkippedTask" }

    observer.on_task_updated(task_class, previous_state: :pending, current_state: :skipped, timestamp: Time.now)

    log_content = @log_output.string
    assert_match(/task\.skipped/, log_content)
    assert_match(/SkippedTask/, log_content)
  end

  def test_on_task_updated_logs_clean_phase_transitions
    observer = Taski::Logging::LoggerObserver.new
    context = Taski::Execution::ExecutionContext.new
    context.current_phase = :clean
    context.add_observer(observer)

    task_class = Class.new
    task_class.define_singleton_method(:name) { "CleanTask" }

    timestamp = Time.now
    observer.on_task_updated(task_class, previous_state: :pending, current_state: :running, timestamp: timestamp)

    log_content = @log_output.string
    assert_match(/task\.clean_started/, log_content)
    assert_match(/CleanTask/, log_content)
  end

  def test_on_task_updated_calculates_duration
    observer = Taski::Logging::LoggerObserver.new
    context = Taski::Execution::ExecutionContext.new
    context.current_phase = :run
    context.add_observer(observer)

    task_class = Class.new
    task_class.define_singleton_method(:name) { "DurationTask" }

    start_time = Time.now
    end_time = start_time + 0.5  # 500ms later

    # Start the task
    observer.on_task_updated(task_class, previous_state: :pending, current_state: :running, timestamp: start_time)

    @log_output.truncate(0)
    @log_output.rewind

    # Complete the task
    observer.on_task_updated(task_class, previous_state: :running, current_state: :completed, timestamp: end_time)

    log_content = @log_output.string
    assert_match(/task\.completed/, log_content)
    assert_match(/duration_ms/, log_content)
    # Duration should be approximately 500ms
    assert_match(/500\.0/, log_content)
  end

  def test_on_task_updated_logs_error_on_failure
    observer = Taski::Logging::LoggerObserver.new
    context = Taski::Execution::ExecutionContext.new
    context.current_phase = :run
    context.add_observer(observer)

    task_class = Class.new
    task_class.define_singleton_method(:name) { "FailedTask" }

    start_time = Time.now
    end_time = start_time + 0.1

    observer.on_task_updated(task_class, previous_state: :pending, current_state: :running, timestamp: start_time)
    @log_output.truncate(0)
    @log_output.rewind

    error = RuntimeError.new("Something went wrong")
    error.set_backtrace(["line1", "line2"])

    observer.on_task_updated(task_class, previous_state: :running, current_state: :failed, timestamp: end_time, error: error)

    log_content = @log_output.string
    assert_match(/task\.failed/, log_content)
    assert_match(/RuntimeError/, log_content)
    assert_match(/Something went wrong/, log_content)
  end
end
