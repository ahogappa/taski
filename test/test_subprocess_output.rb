# frozen_string_literal: true

require "test_helper"

# Tests for system() method override in Task.
# This file focuses on return values and basic functionality.
# Output capture through TaskOutputRouter is tested in test_tree_display.rb.
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
    assert_equal true, task_class.result
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
    assert_equal false, task_class.result
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
    assert_nil task_class.result
  end

  def test_system_with_multiple_arguments
    task_class = Class.new(Taski::Task) do
      exports :result

      def run
        @result = system("echo", "hello", "world")
      end
    end

    task_class.run
    assert_equal true, task_class.result
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
end
