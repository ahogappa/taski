# frozen_string_literal: true

require "minitest/autorun"
require "liquid"
require_relative "../lib/taski/execution/layout/template_drop"
require_relative "../lib/taski/execution/template/base"

class TestTemplateDrop < Minitest::Test
  def setup
    @template = Taski::Execution::Template::Base.new
    @drop = Taski::Execution::Layout::TemplateDrop.new(@template)
  end

  def test_template_drop_inherits_from_liquid_drop
    assert Taski::Execution::Layout::TemplateDrop < Liquid::Drop
  end

  def test_color_red_delegation
    assert_equal @template.color_red, @drop.color_red
    assert_equal "\e[31m", @drop.color_red
  end

  def test_color_green_delegation
    assert_equal @template.color_green, @drop.color_green
    assert_equal "\e[32m", @drop.color_green
  end

  def test_color_yellow_delegation
    assert_equal @template.color_yellow, @drop.color_yellow
    assert_equal "\e[33m", @drop.color_yellow
  end

  def test_color_dim_delegation
    assert_equal @template.color_dim, @drop.color_dim
    assert_equal "\e[2m", @drop.color_dim
  end

  def test_color_reset_delegation
    assert_equal @template.color_reset, @drop.color_reset
    assert_equal "\e[0m", @drop.color_reset
  end

  def test_spinner_frames_delegation
    assert_equal @template.spinner_frames, @drop.spinner_frames
    assert_equal %w[⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏], @drop.spinner_frames
  end

  def test_render_interval_delegation
    assert_equal @template.render_interval, @drop.render_interval
    assert_equal 0.1, @drop.render_interval
  end

  def test_icon_success_delegation
    assert_equal @template.icon_success, @drop.icon_success
    assert_equal "✓", @drop.icon_success
  end

  def test_icon_failure_delegation
    assert_equal @template.icon_failure, @drop.icon_failure
    assert_equal "✗", @drop.icon_failure
  end

  def test_icon_pending_delegation
    assert_equal @template.icon_pending, @drop.icon_pending
    assert_equal "○", @drop.icon_pending
  end

  def test_drop_works_with_custom_template
    custom_template = Class.new(Taski::Execution::Template::Base) do
      def color_red
        "\e[91m"  # bright red
      end

      def spinner_frames
        %w[| / - \\]
      end

      def icon_success
        "[OK]"
      end
    end.new

    custom_drop = Taski::Execution::Layout::TemplateDrop.new(custom_template)

    assert_equal "\e[91m", custom_drop.color_red
    assert_equal %w[| / - \\], custom_drop.spinner_frames
    assert_equal "[OK]", custom_drop.icon_success
    # Non-overridden methods should still work
    assert_equal "\e[32m", custom_drop.color_green
    assert_equal "✗", custom_drop.icon_failure
  end

  def test_drop_can_be_used_in_liquid_context
    environment = Liquid::Environment.build
    liquid_template = Liquid::Template.parse(
      "Color: {{ template.color_red }}",
      environment: environment
    )
    result = liquid_template.render("template" => @drop)

    assert_equal "Color: \e[31m", result
  end

  def test_drop_exposes_spinner_frames_as_array
    environment = Liquid::Environment.build
    liquid_template = Liquid::Template.parse(
      "{% for frame in template.spinner_frames %}{{ frame }}{% endfor %}",
      environment: environment
    )
    result = liquid_template.render("template" => @drop)

    assert_equal "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏", result
  end

  def test_format_count_delegation
    assert_equal @template.format_count(5), @drop.format_count(5)
    assert_equal "5", @drop.format_count(5)
  end

  def test_format_duration_delegation
    assert_equal @template.format_duration(500), @drop.format_duration(500)
    assert_equal "500ms", @drop.format_duration(500)
    assert_equal "1.5s", @drop.format_duration(1500)
  end

  def test_format_methods_with_custom_template
    custom_template = Class.new(Taski::Execution::Template::Base) do
      def format_count(count)
        "#{count}件"
      end

      def format_duration(ms)
        "#{ms}ミリ秒"
      end
    end.new

    custom_drop = Taski::Execution::Layout::TemplateDrop.new(custom_template)

    assert_equal "3件", custom_drop.format_count(3)
    assert_equal "100ミリ秒", custom_drop.format_duration(100)
  end
end
