# frozen_string_literal: true

require "test_helper"

class TestContext < Minitest::Test
  def setup
    # Reset the task system before each test
    Taski::Task.reset! if defined?(Taski::Task)
  end

  def test_working_directory_returns_current_directory
    expected_dir = Dir.pwd

    task_class = Class.new(Taski::Task) do
      exports :captured_dir

      def run
        @captured_dir = Taski::Context.working_directory
      end
    end

    task_class.run
    assert_equal expected_dir, task_class.captured_dir
  end

  def test_started_at_returns_time
    task_class = Class.new(Taski::Task) do
      exports :captured_time

      def run
        @captured_time = Taski::Context.started_at
      end
    end

    before_run = Time.now
    task_class.run
    after_run = Time.now

    assert_kind_of Time, task_class.captured_time
    assert task_class.captured_time >= before_run
    assert task_class.captured_time <= after_run
  end

  def test_root_task_returns_first_called_task
    require_relative "fixtures/parallel_tasks"

    Taski::Task.reset!

    # When we call ParallelTaskC, it should be the root task
    # even though it depends on ParallelTaskA and ParallelTaskB
    ParallelTaskC.task_c_value

    assert_equal ParallelTaskC, Taski::Context.root_task
  end

  def test_root_task_is_set_only_once
    task_a = Class.new(Taski::Task) do
      exports :value

      def run
        @value = "A"
      end
    end

    task_b = Class.new(Taski::Task) do
      exports :value

      def run
        @value = "B"
      end
    end

    # First task call sets root_task
    task_a.value
    first_root = Taski::Context.root_task

    # Second task call should not change root_task
    task_b.value
    second_root = Taski::Context.root_task

    assert_equal task_a, first_root
    assert_equal task_a, second_root
  end

  def test_reset_clears_context
    task_class = Class.new(Taski::Task) do
      exports :value

      def run
        @value = "test"
      end
    end

    task_class.run

    # Context values should be set
    assert_equal task_class, Taski::Context.root_task
    refute_nil Taski::Context.working_directory
    refute_nil Taski::Context.started_at

    # Reset should clear all values
    Taski::Task.reset!

    assert_nil Taski::Context.root_task
  end

  def test_context_is_not_dependency
    require_relative "fixtures/parallel_tasks"

    Taski::Task.reset!

    # Context should not appear in dependencies
    # Note: Static analysis requires actual source files, so we just verify
    # that Context is not a Task subclass (which is how dependencies are filtered)
    refute Taski::Context < Taski::Task
    refute Taski::Context < Taski::Section
  end

  def test_context_thread_safety
    Taski::Task.reset!

    results = []
    mutex = Mutex.new
    threads = []

    # Create multiple threads that try to set root_task simultaneously
    10.times do |i|
      task_class = Class.new(Taski::Task) do
        exports :value

        define_method(:run) do
          @value = i
        end
      end

      threads << Thread.new do
        task_class.value
        mutex.synchronize { results << Taski::Context.root_task }
      end
    end

    threads.each(&:join)

    # All threads should see the same root_task (the first one that was set)
    assert_equal 1, results.uniq.size, "All threads should see the same root_task"
  end

  def test_context_values_are_consistent_during_execution
    require_relative "fixtures/parallel_tasks"

    Taski::Task.reset!

    # Define tasks that capture context values
    task_a = Class.new(Taski::Task) do
      exports :context_info

      define_method(:run) do
        sleep 0.05 # Small delay to ensure parallel execution
        @context_info = {
          root: Taski::Context.root_task,
          dir: Taski::Context.working_directory,
          time: Taski::Context.started_at
        }
      end
    end

    task_b = Class.new(Taski::Task) do
      exports :context_info

      define_method(:run) do
        sleep 0.05
        @context_info = {
          root: Taski::Context.root_task,
          dir: Taski::Context.working_directory,
          time: Taski::Context.started_at
        }
      end
    end

    # Access both tasks
    task_a.context_info
    task_b.context_info

    # Both tasks should see consistent context values
    assert_equal task_a.context_info[:dir], task_b.context_info[:dir]
    assert_equal task_a.context_info[:time], task_b.context_info[:time]
  end
end
