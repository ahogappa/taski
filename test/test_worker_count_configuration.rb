# frozen_string_literal: true

require_relative "test_helper"

class TestWorkerCountConfiguration < Minitest::Test
  def setup
    Taski.reset_args!
    Taski.reset_progress_display!
  end

  def teardown
    Taski.reset_args!
    Taski.reset_progress_display!
  end

  # ========================================
  # Task.run with workers parameter
  # ========================================

  class SimpleTask < Taski::Task
    exports :result

    def run
      @result = "done"
    end
  end

  def test_run_accepts_workers_parameter
    SimpleTask.reset!
    SimpleTask.run(workers: 2)
    assert_equal "done", SimpleTask.result
  end

  def test_clean_accepts_workers_parameter
    SimpleTask.reset!
    SimpleTask.run
    SimpleTask.clean(workers: 2)
  end

  def test_run_and_clean_accepts_workers_parameter
    SimpleTask.reset!
    SimpleTask.run_and_clean(workers: 2)
    assert_equal "done", SimpleTask.result
  end

  def test_run_with_workers_1_for_sequential_execution
    SimpleTask.reset!
    SimpleTask.run(workers: 1)
    assert_equal "done", SimpleTask.result
  end

  # ========================================
  # Integration: Verify worker count flows through
  # ========================================

  class SlowTask < Taski::Task
    exports :thread_id

    def run
      sleep 0.05
      @thread_id = Thread.current.object_id
    end
  end

  class ParentTask < Taski::Task
    exports :result, :slow_task_thread_id

    def run
      @slow_task_thread_id = SlowTask.thread_id
      @result = @slow_task_thread_id
    end
  end

  def test_workers_parameter_is_passed_to_executor
    ParentTask.reset!
    SlowTask.reset!

    # Capture thread ID during execution
    captured_thread_id = nil

    task_class = Class.new(Taski::Task) do
      exports :result

      define_method(:run) do
        captured_thread_id = SlowTask.thread_id
        @result = captured_thread_id
      end
    end

    result = task_class.run(workers: 1)

    # Verify execution completed with valid thread ID
    refute_nil captured_thread_id
    assert_kind_of Integer, captured_thread_id
    assert_equal result, captured_thread_id
  end

  def test_sequential_execution_with_workers_1
    ParentTask.reset!
    SlowTask.reset!

    ParentTask.run(workers: 1)
    refute_nil SlowTask.thread_id
  end

  # ========================================
  # Args worker count API
  # ========================================

  def test_args_worker_count_returns_nil_without_args
    assert_nil Taski.args_worker_count
  end

  def test_args_worker_count_returns_nil_when_not_set
    Taski.start_args(options: {}, root_task: nil)
    assert_nil Taski.args_worker_count
  end

  def test_args_worker_count_returns_value_when_set
    Taski.start_args(options: {_workers: 4}, root_task: nil)
    assert_equal 4, Taski.args_worker_count
  end

  # ========================================
  # Validation tests
  # ========================================

  def test_run_raises_error_for_zero_workers
    SimpleTask.reset!
    error = assert_raises(ArgumentError) { SimpleTask.run(workers: 0) }
    assert_match(/workers must be a positive integer or nil/, error.message)
  end

  def test_run_raises_error_for_negative_workers
    SimpleTask.reset!
    error = assert_raises(ArgumentError) { SimpleTask.run(workers: -1) }
    assert_match(/workers must be a positive integer or nil/, error.message)
  end

  def test_run_raises_error_for_non_integer_workers
    SimpleTask.reset!
    error = assert_raises(ArgumentError) { SimpleTask.run(workers: "4") }
    assert_match(/workers must be a positive integer or nil/, error.message)
  end

  def test_clean_raises_error_for_invalid_workers
    SimpleTask.reset!
    error = assert_raises(ArgumentError) { SimpleTask.clean(workers: 0) }
    assert_match(/workers must be a positive integer or nil/, error.message)
  end

  def test_run_and_clean_raises_error_for_invalid_workers
    SimpleTask.reset!
    error = assert_raises(ArgumentError) { SimpleTask.run_and_clean(workers: -5) }
    assert_match(/workers must be a positive integer or nil/, error.message)
  end

  # ========================================
  # Combined args and workers test
  # ========================================

  def test_workers_parameter_with_args_options
    SimpleTask.reset!
    SimpleTask.run(args: {custom_key: "value"}, workers: 4)
    assert_equal "done", SimpleTask.result
  end
end
