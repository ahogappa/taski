# frozen_string_literal: true

require "test_helper"
require_relative "fixtures/subprocess_output_tasks"

# Tests for system() method override in Task.
# This file focuses on return values and basic functionality.
# Output capture through TaskOutputRouter is tested in test_tree_display.rb.
class TestSubprocessOutput < Minitest::Test
  def setup
    Taski::Task.reset! if defined?(Taski::Task)
  end

  # Tests for system() method override - return values

  def test_system_returns_true_on_success
    result = SubprocessOutputFixtures::SystemSuccessTask.run
    assert_equal true, result
  end

  def test_system_returns_false_on_failure
    result = SubprocessOutputFixtures::SystemFailureTask.run
    assert_equal false, result
  end

  def test_system_returns_nil_on_command_not_found
    result = SubprocessOutputFixtures::SystemNotFoundTask.run
    assert_nil result
  end

  def test_system_with_multiple_arguments
    result = SubprocessOutputFixtures::SystemMultiArgsTask.run
    assert_equal true, result
  end

  # Tests for option handling

  def test_system_with_environment_variables
    result = SubprocessOutputFixtures::SystemEnvVarsTask.run
    assert_equal true, result
  end

  def test_system_with_chdir_option
    result = SubprocessOutputFixtures::SystemChdirTask.run
    assert_equal true, result
  end

  def test_system_respects_user_provided_out_option
    result = SubprocessOutputFixtures::SystemUserOutTask.run
    assert_equal true, result
  end

  def test_system_with_env_and_options_combined
    result = SubprocessOutputFixtures::SystemEnvAndOptionsTask.run
    assert_equal true, result
  end
end
