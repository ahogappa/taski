# frozen_string_literal: true

require "test_helper"

class TestEnv < Minitest::Test
  def setup
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

  def test_env_cleared_after_execution
    captured_env = nil

    task_class = Class.new(Taski::Task) do
      exports :value

      define_method(:run) do
        captured_env = Taski.env
        @value = "test"
      end
    end

    task_class.run

    refute_nil captured_env
    assert_equal task_class, captured_env.root_task
    refute_nil captured_env.working_directory
    refute_nil captured_env.started_at

    assert_nil Taski.env
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
end
