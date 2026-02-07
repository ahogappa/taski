# frozen_string_literal: true

require "test_helper"

class TestArgs < Minitest::Test
  def setup
    # Reset the task system before each test
    Taski::Task.reset! if defined?(Taski::Task)
  end

  def test_working_directory_returns_current_directory
    expected_dir = Dir.pwd
    captured_dir = nil

    task_class = Class.new(Taski::Task) do
      exports :captured_dir

      define_method(:run) do
        captured_dir = Taski.env.working_directory
        @captured_dir = captured_dir
      end
    end

    task_class.run
    assert_equal expected_dir, captured_dir
  end

  def test_started_at_returns_time
    captured_time = nil

    task_class = Class.new(Taski::Task) do
      exports :captured_time

      define_method(:run) do
        captured_time = Taski.env.started_at
        @captured_time = captured_time
      end
    end

    before_run = Time.now
    task_class.run
    after_run = Time.now

    assert_kind_of Time, captured_time
    assert captured_time >= before_run
    assert captured_time <= after_run
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
    captured_args = nil

    task_class = Class.new(Taski::Task) do
      exports :result

      define_method(:run) do
        captured_args = Taski.args
        @result = Taski.args[:env]
      end
    end

    result = task_class.run(args: {env: "production"})
    assert_equal "production", result

    # Args exposes only read methods — no mutation methods exist
    refute_respond_to captured_args, :[]=
    refute_respond_to captured_args, :delete
    refute_respond_to captured_args, :merge!
    refute_respond_to captured_args, :store
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
