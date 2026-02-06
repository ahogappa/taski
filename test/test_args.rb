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
        @captured_dir = Taski.env.working_directory
      end
    end

    # Use Task.new to cache the result within the instance
    task = task_class.new
    task.run
    assert_equal expected_dir, task.captured_dir
  end

  def test_started_at_returns_time
    task_class = Class.new(Taski::Task) do
      exports :captured_time

      def run
        @captured_time = Taski.env.started_at
      end
    end

    before_run = Time.now
    # Use instance to get cached value
    task = task_class.new
    task.run
    after_run = Time.now

    assert_kind_of Time, task.captured_time
    assert task.captured_time >= before_run
    assert task.captured_time <= after_run
  end

  def test_root_task_returns_first_called_task
    captured_root = nil

    task_class = Class.new(Taski::Task) do
      exports :value

      define_method(:run) do
        captured_root = Taski.env.root_task
        @value = "test"
      end
    end

    task_class.run

    # root_task is captured during execution (before reset_env!)
    assert_equal task_class, captured_root
  end

  def test_root_task_is_consistent_during_dependency_execution
    captured_roots = []

    dep_task = Class.new(Taski::Task) do
      exports :value

      define_method(:run) do
        captured_roots << Taski.env.root_task
        @value = "dep"
      end
    end

    # Use Object.const_set to make dep_task accessible
    Object.const_set(:TempDepTask, dep_task) unless Object.const_defined?(:TempDepTask)

    root_task = Class.new(Taski::Task) do
      exports :value

      define_method(:run) do
        captured_roots << Taski.env.root_task
        TempDepTask.value
        captured_roots << Taski.env.root_task
        @value = "root"
      end
    end

    root_task.run

    # All captured root_tasks should be the same (root_task, not dep_task)
    assert_equal 3, captured_roots.size
    assert(captured_roots.all? { |r| r == root_task }, "root_task should be consistent during execution")
  ensure
    Object.send(:remove_const, :TempDepTask) if Object.const_defined?(:TempDepTask)
  end

  def test_args_and_env_cleared_after_execution
    captured_args = nil
    captured_env = nil

    task_class = Class.new(Taski::Task) do
      exports :value

      define_method(:run) do
        captured_args = Taski.args
        captured_env = Taski.env
        @value = "test"
      end
    end

    task_class.run

    # Args and env should be set during execution
    refute_nil captured_args
    refute_nil captured_env
    assert_equal task_class, captured_env.root_task
    refute_nil captured_env.working_directory
    refute_nil captured_env.started_at

    # Args and env should be cleared after execution
    assert_nil Taski.args
    assert_nil Taski.env
  end

  def test_args_is_not_dependency
    require_relative "fixtures/parallel_tasks"

    Taski::Task.reset!

    # Args should not appear in dependencies
    # Note: Static analysis requires actual source files, so we just verify
    # that Args is not a Task subclass (which is how dependencies are filtered)
    refute Taski::Args < Taski::Task
  end

  def test_args_thread_safety
    # In the new design, each Task.run is independent
    # Test that concurrent executions don't interfere with each other
    results = []
    mutex = Mutex.new
    threads = []

    10.times do |i|
      # Each task captures its own value through closure
      execution_values = []

      task_class = Class.new(Taski::Task) do
        exports :value

        define_method(:run) do
          execution_values << i
          @value = i
        end
      end

      threads << Thread.new do
        task_class.run
        mutex.synchronize { results << [i, execution_values.first] }
      end
    end

    threads.each(&:join)

    # Each execution should capture its own value correctly
    results.each do |expected_value, actual_value|
      assert_equal expected_value, actual_value, "Each execution should capture its own value"
    end
  end

  def test_env_values_are_consistent_during_execution
    # Test that env values are consistent within a single execution
    captured_values = []

    dep_task = Class.new(Taski::Task) do
      exports :value

      define_method(:run) do
        captured_values << {
          root: Taski.env.root_task,
          dir: Taski.env.working_directory,
          time: Taski.env.started_at
        }
        @value = "dep"
      end
    end

    Object.const_set(:TempConsistencyDepTask, dep_task) unless Object.const_defined?(:TempConsistencyDepTask)

    root_task = Class.new(Taski::Task) do
      exports :value

      define_method(:run) do
        captured_values << {
          root: Taski.env.root_task,
          dir: Taski.env.working_directory,
          time: Taski.env.started_at
        }
        TempConsistencyDepTask.value
        @value = "root"
      end
    end

    root_task.run

    # Both tasks should see consistent env values within the same execution
    assert_equal 2, captured_values.size
    assert_equal captured_values[0][:dir], captured_values[1][:dir]
    assert_equal captured_values[0][:time], captured_values[1][:time]
    assert_equal captured_values[0][:root], captured_values[1][:root]
  ensure
    Object.send(:remove_const, :TempConsistencyDepTask) if Object.const_defined?(:TempConsistencyDepTask)
  end

  # Tests for user-defined options

  def test_args_options_are_accessible
    captured_env = nil

    task_class = Class.new(Taski::Task) do
      exports :env_value

      define_method(:run) do
        captured_env = Taski.args[:env]
        @env_value = captured_env
      end
    end

    task_class.run(args: {env: "production"})
    assert_equal "production", captured_env
  end

  def test_args_options_return_nil_for_missing_keys
    captured_value = nil

    task_class = Class.new(Taski::Task) do
      exports :missing_value

      define_method(:run) do
        captured_value = Taski.args[:nonexistent]
        @missing_value = captured_value
      end
    end

    task_class.run(args: {env: "production"})
    assert_nil captured_value
  end

  def test_args_fetch_with_default_value
    captured_timeout = nil

    task_class = Class.new(Taski::Task) do
      exports :timeout_value

      define_method(:run) do
        captured_timeout = Taski.args.fetch(:timeout, 30)
        @timeout_value = captured_timeout
      end
    end

    task_class.run(args: {})
    assert_equal 30, captured_timeout
  end

  def test_args_fetch_with_block
    captured_computed = nil

    task_class = Class.new(Taski::Task) do
      exports :computed_value

      define_method(:run) do
        captured_computed = Taski.args.fetch(:computed) { 10 * 5 }
        @computed_value = captured_computed
      end
    end

    task_class.run(args: {})
    assert_equal 50, captured_computed
  end

  def test_args_fetch_returns_existing_value_over_default
    captured_timeout = nil

    task_class = Class.new(Taski::Task) do
      exports :timeout_value

      define_method(:run) do
        captured_timeout = Taski.args.fetch(:timeout, 30)
        @timeout_value = captured_timeout
      end
    end

    task_class.run(args: {timeout: 60})
    assert_equal 60, captured_timeout
  end

  def test_args_key_check
    captured_has_env = nil
    captured_has_missing = nil

    task_class = Class.new(Taski::Task) do
      exports :has_env, :has_missing

      define_method(:run) do
        captured_has_env = Taski.args.key?(:env)
        captured_has_missing = Taski.args.key?(:missing)
        @has_env = captured_has_env
        @has_missing = captured_has_missing
      end
    end

    task_class.run(args: {env: "production"})
    assert captured_has_env
    refute captured_has_missing
  end

  def test_args_options_are_immutable
    captured_frozen = nil

    task_class = Class.new(Taski::Task) do
      exports :result

      define_method(:run) do
        # Options hash should be frozen
        captured_frozen = Taski.args.instance_variable_get(:@options).frozen?
        @result = captured_frozen
      end
    end

    task_class.run(args: {env: "production"})
    assert captured_frozen
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

  # Tests for Task.new(args:) pattern

  def test_task_new_accepts_args_parameter
    captured_env = nil

    task_class = Class.new(Taski::Task) do
      exports :env_value

      define_method(:run) do
        captured_env = Taski.args[:env]
        @env_value = captured_env
      end
    end

    task = task_class.new(args: {env: "test"})
    task.run
    assert_equal "test", captured_env
    assert_equal "test", task.env_value
  end

  def test_task_new_accepts_workers_parameter
    captured_workers = nil

    task_class = Class.new(Taski::Task) do
      exports :workers_value

      define_method(:run) do
        captured_workers = Taski.args_worker_count
        @workers_value = captured_workers
      end
    end

    task = task_class.new(workers: 4)
    task.run
    assert_equal 4, captured_workers
    assert_equal 4, task.workers_value
  end

  def test_task_new_accepts_args_and_workers_together
    captured_env = nil
    captured_workers = nil

    task_class = Class.new(Taski::Task) do
      exports :env_value, :workers_value

      define_method(:run) do
        captured_env = Taski.args[:env]
        captured_workers = Taski.args_worker_count
        @env_value = captured_env
        @workers_value = captured_workers
      end
    end

    task = task_class.new(args: {env: "production"}, workers: 8)
    task.run
    assert_equal "production", captured_env
    assert_equal 8, captured_workers
  end

  def test_task_new_validates_workers_parameter
    task_class = Class.new(Taski::Task) do
      exports :value
      def run
        @value = "done"
      end
    end

    # Zero workers should raise
    error = assert_raises(ArgumentError) { task_class.new(workers: 0) }
    assert_match(/workers must be a positive integer/, error.message)

    # Negative workers should raise
    error = assert_raises(ArgumentError) { task_class.new(workers: -1) }
    assert_match(/workers must be a positive integer/, error.message)

    # Non-integer should raise
    error = assert_raises(ArgumentError) { task_class.new(workers: "2") }
    assert_match(/workers must be a positive integer/, error.message)
  end

  def test_task_new_run_then_clean_with_instance_variables
    cleanup_called = false
    created_file = nil

    task_class = Class.new(Taski::Task) do
      exports :file_path

      define_method(:run) do
        @file_path = "/tmp/test_file_#{object_id}"
        created_file = @file_path
      end

      define_method(:clean) do
        cleanup_called = true
        # In real usage, would delete the file using @file_path
      end
    end

    task = task_class.new
    task.run
    assert_equal created_file, task.file_path

    task.clean
    assert cleanup_called
  end

  def test_task_new_returns_task_wrapper
    task_class = Class.new(Taski::Task) do
      exports :value
      def run
        @value = "done"
      end
    end

    task = task_class.new
    assert_instance_of Taski::Execution::TaskWrapper, task
  end
end
