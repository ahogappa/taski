# frozen_string_literal: true

require "test_helper"

class TestArgs < Minitest::Test
  def setup
    # Reset the task system before each test
    Taski::Task.reset! if defined?(Taski::Task)
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
    captured_value = nil
    mutation_error = nil

    task_class = Class.new(Taski::Task) do
      exports :result

      define_method(:run) do
        captured_value = Taski.args[:env]
        begin
          Taski.args.instance_variable_get(:@options)[:env] = "staging"
        rescue => e
          mutation_error = e
        end
        @result = captured_value
      end
    end

    task_class.run(args: {env: "production"})
    assert_equal "production", captured_value
    assert_kind_of FrozenError, mutation_error
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
