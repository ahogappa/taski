# frozen_string_literal: true

require "test_helper"

# Tests for system() method override in Task.
# This file focuses on return values and basic functionality.
# Output capture through OutputHub is tested in test_tree_display.rb.
class TestSubprocessOutput < Minitest::Test
  def setup
    Taski::Task.reset! if defined?(Taski::Task)
  end

  # Tests for system() method override - return values

  def test_system_returns_true_on_success
    task_class = Class.new(Taski::Task) do
      exports :result

      def run
        @result = system("echo hello")
      end
    end

    result = task_class.run
    assert_equal true, result
  end

  def test_system_returns_false_on_failure
    task_class = Class.new(Taski::Task) do
      exports :result

      def run
        @result = system("exit 1")
      end
    end

    result = task_class.run
    assert_equal false, result
  end

  def test_system_returns_nil_on_command_not_found
    task_class = Class.new(Taski::Task) do
      exports :result

      def run
        @result = system("nonexistent_command_xyz123")
      end
    end

    result = task_class.run
    assert_nil result
  end

  def test_system_with_multiple_arguments
    task_class = Class.new(Taski::Task) do
      exports :result

      def run
        @result = system("echo", "hello", "world")
      end
    end

    result = task_class.run
    assert_equal true, result
  end

  # Test that system works with fresh TaskWrapper instances

  def test_system_with_new_instance
    task_class = Class.new(Taski::Task) do
      exports :result

      def run
        @result = system("echo from_new_instance")
      end
    end

    task = task_class.new
    task.run
    assert_equal true, task.result
  end

  # Tests for option handling

  def test_system_with_environment_variables
    task_class = Class.new(Taski::Task) do
      exports :result

      def run
        # Environment variable hash as first argument
        @result = system({"TEST_VAR" => "hello_from_env"}, "echo $TEST_VAR")
      end
    end

    result = task_class.run
    assert_equal true, result
  end

  def test_system_with_chdir_option
    task_class = Class.new(Taski::Task) do
      exports :result

      def run
        # :chdir option should be preserved and passed through
        @result = system("pwd", chdir: "/tmp")
      end
    end

    result = task_class.run
    assert_equal true, result
  end

  def test_system_respects_user_provided_out_option
    task_class = Class.new(Taski::Task) do
      exports :result

      def run
        # When user provides :out, it should not be overwritten
        @result = system("echo test", out: File::NULL)
      end
    end

    result = task_class.run
    assert_equal true, result
  end

  def test_system_with_env_and_options_combined
    task_class = Class.new(Taski::Task) do
      exports :result

      def run
        # Environment variables + options should both work
        @result = system({"MY_VAR" => "value"}, "echo $MY_VAR", chdir: "/tmp")
      end
    end

    result = task_class.run
    assert_equal true, result
  end
end
