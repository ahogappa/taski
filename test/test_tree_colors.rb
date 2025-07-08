# frozen_string_literal: true

require_relative "test_helper"

class TestTreeColors < Minitest::Test
  include TaskiTestHelper

  def setup
    setup_taski_test
    # Ensure colors are enabled for testing
    Taski::TreeDisplay::TreeColors.enabled = true
  end

  def teardown
    # Reset to default state
    Taski::TreeDisplay::TreeColors.enabled = nil
  end

  def test_section_colorization
    result = Taski::TreeDisplay::TreeColors.section("MySection")
    assert_includes result, "\e[1m", "Should include bold formatting"
    assert_includes result, "\e[34m", "Should include blue color"
    assert_includes result, "MySection", "Should include original text"
    assert_includes result, "\e[0m", "Should include reset code"
  end

  def test_task_colorization
    result = Taski::TreeDisplay::TreeColors.task("MyTask")
    assert_includes result, "\e[32m", "Should include green color"
    assert_includes result, "MyTask", "Should include original text"
    assert_includes result, "\e[0m", "Should include reset code"
    refute_includes result, "\e[1m", "Should not include bold formatting"
  end

  def test_implementations_colorization
    result = Taski::TreeDisplay::TreeColors.implementations("[One of: A, B]")
    assert_includes result, "\e[33m", "Should include yellow color"
    assert_includes result, "[One of: A, B]", "Should include original text"
    assert_includes result, "\e[0m", "Should include reset code"
  end

  def test_connector_colorization
    result = Taski::TreeDisplay::TreeColors.connector("├── ")
    assert_includes result, "\e[90m", "Should include gray color"
    assert_includes result, "├── ", "Should include original text"
    assert_includes result, "\e[0m", "Should include reset code"
  end

  def test_colors_disabled
    Taski::TreeDisplay::TreeColors.enabled = false

    result = Taski::TreeDisplay::TreeColors.section("MySection")
    assert_equal "MySection", result, "Should return plain text when disabled"

    result = Taski::TreeDisplay::TreeColors.task("MyTask")
    assert_equal "MyTask", result, "Should return plain text when disabled"
  end

  def test_enabled_detection
    # Test with mocked TTY and NO_COLOR environment
    original_no_color = ENV["NO_COLOR"]

    # Reset enabled state to test detection
    Taski::TreeDisplay::TreeColors.enabled = nil

    # Mock TTY detection (assuming we're in a TTY environment)
    def $stdout.tty?
      true
    end

    ENV.delete("NO_COLOR")
    assert Taski::TreeDisplay::TreeColors.enabled?, "Should be enabled in TTY without NO_COLOR"

    ENV["NO_COLOR"] = "1"
    # Reset to force re-detection
    Taski::TreeDisplay::TreeColors.enabled = nil
    refute Taski::TreeDisplay::TreeColors.enabled?, "Should be disabled when NO_COLOR is set"
  ensure
    # Restore original state
    if original_no_color
      ENV["NO_COLOR"] = original_no_color
    else
      ENV.delete("NO_COLOR")
    end
    # Restore TTY method (not actually needed in test, but good practice)
  end
end
