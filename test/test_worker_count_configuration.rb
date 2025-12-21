# frozen_string_literal: true

require_relative "test_helper"

class TestWorkerCountConfiguration < Minitest::Test
  def setup
    Taski.reset_global_registry!
    Taski.reset_context!
    Taski.reset_progress_display!
  end

  def teardown
    Taski.reset_global_registry!
    Taski.reset_context!
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
    exports :result

    def run
      @result = SlowTask.thread_id
    end
  end

  def test_workers_parameter_is_passed_to_executor
    ParentTask.reset!
    SlowTask.reset!

    result = ParentTask.run(workers: 1)
    assert_equal result, SlowTask.thread_id
  end

  def test_sequential_execution_with_workers_1
    ParentTask.reset!
    SlowTask.reset!

    ParentTask.run(workers: 1)
    refute_nil SlowTask.thread_id
  end

  # ========================================
  # Context worker count API
  # ========================================

  def test_context_worker_count_returns_nil_without_context
    assert_nil Taski.context_worker_count
  end

  def test_context_worker_count_returns_nil_when_not_set
    Taski.start_context(options: {}, root_task: nil)
    assert_nil Taski.context_worker_count
  end

  def test_context_worker_count_returns_value_when_set
    Taski.start_context(options: {_workers: 4}, root_task: nil)
    assert_equal 4, Taski.context_worker_count
  end
end
