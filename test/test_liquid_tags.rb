# frozen_string_literal: true

require "minitest/autorun"
require "liquid"
require_relative "../lib/taski/progress/layout/tags"
require_relative "../lib/taski/progress/layout/template_drop"
require_relative "../lib/taski/progress/template/base"

class TestLiquidTags < Minitest::Test
  def setup
    @environment = Liquid::Environment.build do |env|
      env.register_tag("spinner", Taski::Progress::Layout::SpinnerTag)
      env.register_tag("icon", Taski::Progress::Layout::IconTag)
    end
  end

  def test_spinner_tag_inherits_from_liquid_tag
    assert Taski::Progress::Layout::SpinnerTag < Liquid::Tag
  end

  def test_spinner_tag_renders_first_frame_by_default
    template_obj = Taski::Progress::Template::Base.new
    drop = Taski::Progress::Layout::TemplateDrop.new(template_obj)

    liquid_template = Liquid::Template.parse("{% spinner %}", environment: @environment)
    result = liquid_template.render("template" => drop)

    # Default frames start with ⠋
    assert_equal "⠋", result
  end

  def test_spinner_tag_uses_spinner_index_from_context
    template_obj = Taski::Progress::Template::Base.new
    drop = Taski::Progress::Layout::TemplateDrop.new(template_obj)

    liquid_template = Liquid::Template.parse("{% spinner %}", environment: @environment)
    result = liquid_template.render("template" => drop, "spinner_index" => 3)

    # Default frames: ⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏
    # Index 3 should be ⠸
    assert_equal "⠸", result
  end

  def test_spinner_tag_wraps_around_when_index_exceeds_frames
    template_obj = Taski::Progress::Template::Base.new
    drop = Taski::Progress::Layout::TemplateDrop.new(template_obj)

    liquid_template = Liquid::Template.parse("{% spinner %}", environment: @environment)
    result = liquid_template.render("template" => drop, "spinner_index" => 10)

    # Index 10 % 10 = 0, should return first frame ⠋
    assert_equal "⠋", result
  end

  def test_spinner_tag_uses_custom_frames_from_template
    custom_template = Class.new(Taski::Progress::Template::Base) do
      def spinner_frames
        %w[| / - \\]
      end
    end.new

    drop = Taski::Progress::Layout::TemplateDrop.new(custom_template)

    liquid_template = Liquid::Template.parse("{% spinner %}", environment: @environment)

    result0 = liquid_template.render("template" => drop, "spinner_index" => 0)
    result1 = liquid_template.render("template" => drop, "spinner_index" => 1)
    result2 = liquid_template.render("template" => drop, "spinner_index" => 2)

    assert_equal "|", result0
    assert_equal "/", result1
    assert_equal "-", result2
  end

  def test_spinner_tag_without_template_drop_uses_default
    liquid_template = Liquid::Template.parse("{% spinner %}", environment: @environment)
    result = liquid_template.render({})

    # Should use default frames, first frame
    assert_equal "⠋", result
  end

  def test_spinner_tag_can_be_combined_with_text
    template_obj = Taski::Progress::Template::Base.new
    drop = Taski::Progress::Layout::TemplateDrop.new(template_obj)

    liquid_template = Liquid::Template.parse(
      "{% spinner %} Loading {{ task_name }}...",
      environment: @environment
    )
    result = liquid_template.render(
      "template" => drop,
      "spinner_index" => 0,
      "task_name" => "MyTask"
    )

    assert_equal "⠋ Loading MyTask...", result
  end

  # === IconTag tests ===

  def test_icon_tag_inherits_from_liquid_tag
    assert Taski::Progress::Layout::IconTag < Liquid::Tag
  end

  def test_icon_tag_renders_success_icon_for_completed_state
    template_obj = Taski::Progress::Template::Base.new
    drop = Taski::Progress::Layout::TemplateDrop.new(template_obj)

    liquid_template = Liquid::Template.parse("{% icon %}", environment: @environment)
    result = liquid_template.render("template" => drop, "state" => "completed")

    assert_equal "\e[32m✓\e[0m", result
  end

  def test_icon_tag_renders_failure_icon_for_failed_state
    template_obj = Taski::Progress::Template::Base.new
    drop = Taski::Progress::Layout::TemplateDrop.new(template_obj)

    liquid_template = Liquid::Template.parse("{% icon %}", environment: @environment)
    result = liquid_template.render("template" => drop, "state" => "failed")

    assert_equal "\e[31m✗\e[0m", result
  end

  def test_icon_tag_renders_pending_icon_for_running_state
    template_obj = Taski::Progress::Template::Base.new
    drop = Taski::Progress::Layout::TemplateDrop.new(template_obj)

    liquid_template = Liquid::Template.parse("{% icon %}", environment: @environment)
    result = liquid_template.render("template" => drop, "state" => "running")

    assert_equal "\e[33m○\e[0m", result
  end

  def test_icon_tag_renders_pending_icon_for_pending_state
    template_obj = Taski::Progress::Template::Base.new
    drop = Taski::Progress::Layout::TemplateDrop.new(template_obj)

    liquid_template = Liquid::Template.parse("{% icon %}", environment: @environment)
    result = liquid_template.render("template" => drop, "state" => "pending")

    assert_equal "○", result
  end

  def test_icon_tag_without_state_renders_pending
    template_obj = Taski::Progress::Template::Base.new
    drop = Taski::Progress::Layout::TemplateDrop.new(template_obj)

    liquid_template = Liquid::Template.parse("{% icon %}", environment: @environment)
    result = liquid_template.render("template" => drop)

    assert_equal "○", result
  end

  def test_icon_tag_uses_custom_template_icons
    custom_template = Class.new(Taski::Progress::Template::Base) do
      def icon_success
        "🎉"
      end

      def color_green
        "\e[92m"
      end
    end.new

    drop = Taski::Progress::Layout::TemplateDrop.new(custom_template)

    liquid_template = Liquid::Template.parse("{% icon %}", environment: @environment)
    result = liquid_template.render("template" => drop, "state" => "completed")

    assert_equal "\e[92m🎉\e[0m", result
  end

  def test_icon_tag_without_template_uses_defaults
    liquid_template = Liquid::Template.parse("{% icon %}", environment: @environment)
    result = liquid_template.render("state" => "completed")

    assert_equal "\e[32m✓\e[0m", result
  end
end
