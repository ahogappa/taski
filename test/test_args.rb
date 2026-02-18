# frozen_string_literal: true

require "test_helper"
require_relative "fixtures/args_tasks"

class TestArgs < Minitest::Test
  def setup
    # Reset the task system before each test
    Taski::Task.reset! if defined?(Taski::Task)
    ArgsFixtures::CapturedValues.clear
  end

  def test_working_directory_returns_current_directory
    expected_dir = Dir.pwd

    ArgsFixtures::WorkingDirectoryTask.run
    captured_dir = ArgsFixtures::CapturedValues.get(:working_directory)
    assert_equal expected_dir, captured_dir
  end

  def test_started_at_returns_time
    before_run = Time.now
    ArgsFixtures::StartedAtTask.run
    after_run = Time.now

    captured_time = ArgsFixtures::CapturedValues.get(:started_at)
    assert_kind_of Time, captured_time
    assert captured_time >= before_run
    assert captured_time <= after_run
  end

  def test_root_task_returns_first_called_task
    ArgsFixtures::RootTaskCaptureTask.run

    captured_root = ArgsFixtures::CapturedValues.get(:root_task)
    assert_equal ArgsFixtures::RootTaskCaptureTask, captured_root
  end

  def test_root_task_is_consistent_during_dependency_execution
    ArgsFixtures::RootConsistencyTask.run

    root_before = ArgsFixtures::CapturedValues.get(:root_before)
    dep_root = ArgsFixtures::CapturedValues.get(:dep_root)
    root_after = ArgsFixtures::CapturedValues.get(:root_after)

    # All captured root_tasks should be the same (RootConsistencyTask, not DepTask)
    assert_equal ArgsFixtures::RootConsistencyTask, root_before
    assert_equal ArgsFixtures::RootConsistencyTask, dep_root
    assert_equal ArgsFixtures::RootConsistencyTask, root_after
  end

  def test_args_and_env_cleared_after_execution
    ArgsFixtures::ArgsAndEnvCaptureTask.run

    captured_args = ArgsFixtures::CapturedValues.get(:captured_args)
    captured_env = ArgsFixtures::CapturedValues.get(:captured_env)

    # Args and env should be set during execution
    refute_nil captured_args
    refute_nil captured_env
    assert_equal ArgsFixtures::ArgsAndEnvCaptureTask, captured_env.root_task
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
    # Intentionally inline: each iteration creates a unique anonymous class with
    # a per-iteration closure. This is fundamentally incompatible with fixtures
    # since the closure captures the loop variable `i`.
    results = []
    mutex = Mutex.new
    threads = []

    10.times do |i|
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
    ArgsFixtures::EnvCaptureRoot.run

    root_env = ArgsFixtures::CapturedValues.get(:root_env)
    dep_env = ArgsFixtures::CapturedValues.get(:dep_env)

    # Both tasks should see consistent env values within the same execution
    refute_nil root_env
    refute_nil dep_env
    assert_equal root_env[:dir], dep_env[:dir]
    assert_equal root_env[:time], dep_env[:time]
    assert_equal root_env[:root], dep_env[:root]
  end

  # Tests for user-defined options

  def test_args_options_are_accessible
    ArgsFixtures::ArgsOptionsCaptureTask.run(args: {env: "production"})
    captured_env = ArgsFixtures::CapturedValues.get(:args_env)
    assert_equal "production", captured_env
  end

  def test_args_options_return_nil_for_missing_keys
    ArgsFixtures::ArgsMissingKeyCaptureTask.run(args: {env: "production"})
    captured_value = ArgsFixtures::CapturedValues.get(:args_missing)
    assert_nil captured_value
  end

  def test_args_fetch_with_default_value
    ArgsFixtures::ArgsFetchDefaultTask.run(args: {})
    captured_timeout = ArgsFixtures::CapturedValues.get(:fetch_default)
    assert_equal 30, captured_timeout
  end

  def test_args_fetch_with_block
    ArgsFixtures::ArgsFetchBlockTask.run(args: {})
    captured_computed = ArgsFixtures::CapturedValues.get(:fetch_block)
    assert_equal 50, captured_computed
  end

  def test_args_fetch_returns_existing_value_over_default
    ArgsFixtures::ArgsFetchExistingTask.run(args: {timeout: 60})
    captured_timeout = ArgsFixtures::CapturedValues.get(:fetch_existing)
    assert_equal 60, captured_timeout
  end

  def test_args_key_check
    ArgsFixtures::ArgsKeyCheckTask.run(args: {env: "production"})
    assert ArgsFixtures::CapturedValues.get(:has_env)
    refute ArgsFixtures::CapturedValues.get(:has_missing)
  end

  def test_args_options_are_immutable
    result = ArgsFixtures::ArgsImmutabilityTask.run(args: {env: "production"})
    assert_equal "production", result

    captured_args = ArgsFixtures::CapturedValues.get(:args_ref)
    # Args exposes only read methods — no mutation methods exist
    refute_respond_to captured_args, :[]=
    refute_respond_to captured_args, :delete
    refute_respond_to captured_args, :merge!
    refute_respond_to captured_args, :store
  end

  def test_args_options_shared_across_dependent_tasks
    ArgsFixtures::ArgsMainTask.run(args: {env: "staging"})

    dep_env = ArgsFixtures::CapturedValues.get(:dep_env_arg)
    assert_equal "staging", dep_env
  end

  # Tests for class accessor with args

  def test_class_accessor_accepts_args
    result = ArgsFixtures::ExportedWithArgsTask.greeting(args: {name: "taski"})
    assert_equal "hello, taski", result
  end

  def test_class_accessor_without_args_uses_empty_default
    result = ArgsFixtures::ExportedWithArgsTask.greeting
    assert_equal "hello, world", result
  end

  def test_class_accessor_args_propagate_to_dependencies
    result = ArgsFixtures::ExportedWithArgsRootTask.combined(args: {name: "taski"})
    assert_equal "dep: taski + root", result
  end

  def test_class_accessor_warns_when_args_passed_inside_execution
    registry = Taski::Execution::Registry.new
    Taski.set_current_registry(registry)
    _out, err = capture_io do
      ArgsFixtures::ExportedWithArgsTask.greeting(args: {name: "ignored"})
    end
    assert_match(/args:.*ignored.*inside.*execution/i, err)
  ensure
    Taski.clear_current_registry
  end
end
