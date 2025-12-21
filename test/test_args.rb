# frozen_string_literal: true

require "test_helper"

class TestArgs < Minitest::Test
  def setup
    # Reset the task system before each test
    Taski::Task.reset! if defined?(Taski::Task)
  end

  def test_working_directory_returns_current_directory
    expected_dir = Dir.pwd

    task_class = Class.new(Taski::Task) do
      exports :captured_dir

      def run
        @captured_dir = Taski.args.working_directory
      end
    end

    task_class.run
    assert_equal expected_dir, task_class.captured_dir
  end

  def test_started_at_returns_time
    task_class = Class.new(Taski::Task) do
      exports :captured_time

      def run
        @captured_time = Taski.args.started_at
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

    assert_equal ParallelTaskC, Taski.args.root_task
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
    first_root = Taski.args.root_task

    # Second task call should not change root_task
    task_b.value
    second_root = Taski.args.root_task

    assert_equal task_a, first_root
    assert_equal task_a, second_root
  end

  def test_reset_clears_args
    task_class = Class.new(Taski::Task) do
      exports :value

      def run
        @value = "test"
      end
    end

    task_class.run

    # Args values should be set
    assert_equal task_class, Taski.args.root_task
    refute_nil Taski.args.working_directory
    refute_nil Taski.args.started_at

    # Reset should clear all values
    Taski::Task.reset!

    assert_nil Taski.args
  end

  def test_args_is_not_dependency
    require_relative "fixtures/parallel_tasks"

    Taski::Task.reset!

    # Args should not appear in dependencies
    # Note: Static analysis requires actual source files, so we just verify
    # that Args is not a Task subclass (which is how dependencies are filtered)
    refute Taski::Args < Taski::Task
    refute Taski::Args < Taski::Section
  end

  def test_args_thread_safety
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
        mutex.synchronize { results << Taski.args.root_task }
      end
    end

    threads.each(&:join)

    # All threads should see the same root_task (the first one that was set)
    assert_equal 1, results.uniq.size, "All threads should see the same root_task"
  end

  def test_args_values_are_consistent_during_execution
    require_relative "fixtures/parallel_tasks"

    Taski::Task.reset!

    # Define tasks that capture args values
    task_a = Class.new(Taski::Task) do
      exports :args_info

      define_method(:run) do
        sleep 0.05 # Small delay to ensure parallel execution
        @args_info = {
          root: Taski.args.root_task,
          dir: Taski.args.working_directory,
          time: Taski.args.started_at
        }
      end
    end

    task_b = Class.new(Taski::Task) do
      exports :args_info

      define_method(:run) do
        sleep 0.05
        @args_info = {
          root: Taski.args.root_task,
          dir: Taski.args.working_directory,
          time: Taski.args.started_at
        }
      end
    end

    # Access both tasks
    task_a.args_info
    task_b.args_info

    # Both tasks should see consistent args values
    assert_equal task_a.args_info[:dir], task_b.args_info[:dir]
    assert_equal task_a.args_info[:time], task_b.args_info[:time]
  end

  # Tests for user-defined options

  def test_args_options_are_accessible
    task_class = Class.new(Taski::Task) do
      exports :env_value

      def run
        @env_value = Taski.args[:env]
      end
    end

    task_class.run(args: {env: "production"})
    assert_equal "production", task_class.env_value
  end

  def test_args_options_return_nil_for_missing_keys
    task_class = Class.new(Taski::Task) do
      exports :missing_value

      def run
        @missing_value = Taski.args[:nonexistent]
      end
    end

    task_class.run(args: {env: "production"})
    assert_nil task_class.missing_value
  end

  def test_args_fetch_with_default_value
    task_class = Class.new(Taski::Task) do
      exports :timeout_value

      def run
        @timeout_value = Taski.args.fetch(:timeout, 30)
      end
    end

    task_class.run(args: {})
    assert_equal 30, task_class.timeout_value
  end

  def test_args_fetch_with_block
    task_class = Class.new(Taski::Task) do
      exports :computed_value

      def run
        @computed_value = Taski.args.fetch(:computed) { 10 * 5 }
      end
    end

    task_class.run(args: {})
    assert_equal 50, task_class.computed_value
  end

  def test_args_fetch_returns_existing_value_over_default
    task_class = Class.new(Taski::Task) do
      exports :timeout_value

      def run
        @timeout_value = Taski.args.fetch(:timeout, 30)
      end
    end

    task_class.run(args: {timeout: 60})
    assert_equal 60, task_class.timeout_value
  end

  def test_args_key_check
    task_class = Class.new(Taski::Task) do
      exports :has_env, :has_missing

      def run
        @has_env = Taski.args.key?(:env)
        @has_missing = Taski.args.key?(:missing)
      end
    end

    task_class.run(args: {env: "production"})
    assert task_class.has_env
    refute task_class.has_missing
  end

  def test_args_options_are_immutable
    task_class = Class.new(Taski::Task) do
      exports :result

      def run
        # Options hash should be frozen
        @result = Taski.args.instance_variable_get(:@options).frozen?
      end
    end

    task_class.run(args: {env: "production"})
    assert task_class.result
  end

  def test_args_options_shared_across_dependent_tasks
    Taski::Task.reset!

    dependency_env = nil

    dep_task = Class.new(Taski::Task) do
      exports :dep_value

      define_method(:run) do
        dependency_env = Taski.args[:env]
        @dep_value = "from_dep"
      end
    end

    main_task_class = Class.new(Taski::Task) do
      exports :main_value

      define_singleton_method(:dep_task) { dep_task }

      define_method(:run) do
        @main_value = self.class.dep_task.dep_value
      end
    end

    main_task_class.run(args: {env: "staging"})
    assert_equal "staging", dependency_env
  end
end
