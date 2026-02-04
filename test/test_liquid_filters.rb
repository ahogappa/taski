# frozen_string_literal: true

require "minitest/autorun"
require "liquid"
require_relative "../lib/taski/progress/layout/filters"
require_relative "../lib/taski/progress/layout/theme_drop"
require_relative "../lib/taski/progress/theme/base"

class TestLiquidFilters < Minitest::Test
  def setup
    @environment = Liquid::Environment.build do |env|
      env.register_filter(Taski::Progress::Layout::ColorFilter)
    end
  end

  def test_red_filter_with_theme_drop
    theme_obj = Taski::Progress::Theme::Base.new
    drop = Taski::Progress::Layout::ThemeDrop.new(theme_obj)

    liquid_template = Liquid::Template.parse("{{ text | red }}", environment: @environment)
    result = liquid_template.render("text" => "error", "template" => drop)

    assert_equal "\e[31merror\e[0m", result
  end

  def test_green_filter_with_theme_drop
    theme_obj = Taski::Progress::Theme::Base.new
    drop = Taski::Progress::Layout::ThemeDrop.new(theme_obj)

    liquid_template = Liquid::Template.parse("{{ text | green }}", environment: @environment)
    result = liquid_template.render("text" => "success", "template" => drop)

    assert_equal "\e[32msuccess\e[0m", result
  end

  def test_yellow_filter_with_theme_drop
    theme_obj = Taski::Progress::Theme::Base.new
    drop = Taski::Progress::Layout::ThemeDrop.new(theme_obj)

    liquid_template = Liquid::Template.parse("{{ text | yellow }}", environment: @environment)
    result = liquid_template.render("text" => "warning", "template" => drop)

    assert_equal "\e[33mwarning\e[0m", result
  end

  def test_dim_filter_with_theme_drop
    theme_obj = Taski::Progress::Theme::Base.new
    drop = Taski::Progress::Layout::ThemeDrop.new(theme_obj)

    liquid_template = Liquid::Template.parse("{{ text | dim }}", environment: @environment)
    result = liquid_template.render("text" => "subtle", "template" => drop)

    assert_equal "\e[2msubtle\e[0m", result
  end

  def test_red_filter_without_theme_drop_uses_default
    liquid_template = Liquid::Template.parse("{{ text | red }}", environment: @environment)
    result = liquid_template.render("text" => "error")

    assert_equal "\e[31merror\e[0m", result
  end

  def test_green_filter_without_theme_drop_uses_default
    liquid_template = Liquid::Template.parse("{{ text | green }}", environment: @environment)
    result = liquid_template.render("text" => "success")

    assert_equal "\e[32msuccess\e[0m", result
  end

  def test_yellow_filter_without_theme_drop_uses_default
    liquid_template = Liquid::Template.parse("{{ text | yellow }}", environment: @environment)
    result = liquid_template.render("text" => "warning")

    assert_equal "\e[33mwarning\e[0m", result
  end

  def test_dim_filter_without_theme_drop_uses_default
    liquid_template = Liquid::Template.parse("{{ text | dim }}", environment: @environment)
    result = liquid_template.render("text" => "subtle")

    assert_equal "\e[2msubtle\e[0m", result
  end

  def test_filter_uses_custom_theme_colors
    custom_theme = Class.new(Taski::Progress::Theme::Base) do
      def color_red
        "\e[91m"  # bright red
      end

      def color_reset
        "\e[39m"  # default foreground
      end
    end.new

    drop = Taski::Progress::Layout::ThemeDrop.new(custom_theme)

    liquid_template = Liquid::Template.parse("{{ text | red }}", environment: @environment)
    result = liquid_template.render("text" => "custom", "template" => drop)

    assert_equal "\e[91mcustom\e[39m", result
  end

  def test_multiple_filters_in_template
    theme_obj = Taski::Progress::Theme::Base.new
    drop = Taski::Progress::Layout::ThemeDrop.new(theme_obj)

    liquid_template = Liquid::Template.parse(
      "{{ status | green }} - {{ message | dim }}",
      environment: @environment
    )
    result = liquid_template.render(
      "status" => "OK",
      "message" => "completed",
      "template" => drop
    )

    assert_equal "\e[32mOK\e[0m - \e[2mcompleted\e[0m", result
  end

  # === format_count filter tests ===

  def test_format_count_with_theme_drop
    theme_obj = Taski::Progress::Theme::Base.new
    drop = Taski::Progress::Layout::ThemeDrop.new(theme_obj)

    liquid_template = Liquid::Template.parse("{{ count | format_count }}", environment: @environment)
    result = liquid_template.render("count" => 5, "template" => drop)

    assert_equal "5", result
  end

  def test_format_count_without_theme_drop_uses_default
    liquid_template = Liquid::Template.parse("{{ count | format_count }}", environment: @environment)
    result = liquid_template.render("count" => 10)

    assert_equal "10", result
  end

  def test_format_count_with_custom_theme
    custom_theme = Class.new(Taski::Progress::Theme::Base) do
      def format_count(count)
        "#{count}件"
      end
    end.new

    drop = Taski::Progress::Layout::ThemeDrop.new(custom_theme)

    liquid_template = Liquid::Template.parse("{{ count | format_count }}", environment: @environment)
    result = liquid_template.render("count" => 3, "template" => drop)

    assert_equal "3件", result
  end

  def test_format_count_in_progress_display
    theme_obj = Taski::Progress::Theme::Base.new
    drop = Taski::Progress::Layout::ThemeDrop.new(theme_obj)

    liquid_template = Liquid::Template.parse(
      "[{{ done | format_count }}/{{ total | format_count }}]",
      environment: @environment
    )
    result = liquid_template.render("done" => 3, "total" => 5, "template" => drop)

    assert_equal "[3/5]", result
  end

  # === format_duration filter tests ===

  def test_format_duration_milliseconds
    theme_obj = Taski::Progress::Theme::Base.new
    drop = Taski::Progress::Layout::ThemeDrop.new(theme_obj)

    liquid_template = Liquid::Template.parse("{{ duration | format_duration }}", environment: @environment)
    result = liquid_template.render("duration" => 500, "template" => drop)

    assert_equal "500ms", result
  end

  def test_format_duration_seconds
    theme_obj = Taski::Progress::Theme::Base.new
    drop = Taski::Progress::Layout::ThemeDrop.new(theme_obj)

    liquid_template = Liquid::Template.parse("{{ duration | format_duration }}", environment: @environment)
    result = liquid_template.render("duration" => 1500, "template" => drop)

    assert_equal "1.5s", result
  end

  def test_format_duration_without_theme_drop_uses_default
    liquid_template = Liquid::Template.parse("{{ duration | format_duration }}", environment: @environment)
    result = liquid_template.render("duration" => 2000)

    assert_equal "2.0s", result
  end

  def test_format_duration_with_custom_theme
    custom_theme = Class.new(Taski::Progress::Theme::Base) do
      def format_duration(ms)
        "#{ms}ミリ秒"
      end
    end.new

    drop = Taski::Progress::Layout::ThemeDrop.new(custom_theme)

    liquid_template = Liquid::Template.parse("{{ duration | format_duration }}", environment: @environment)
    result = liquid_template.render("duration" => 100, "template" => drop)

    assert_equal "100ミリ秒", result
  end

  def test_format_duration_with_nil
    liquid_template = Liquid::Template.parse("{{ duration | format_duration }}", environment: @environment)
    result = liquid_template.render("duration" => nil)

    assert_equal "", result
  end

  # === truncate_list filter tests ===

  def test_truncate_list_with_array
    theme_obj = Taski::Progress::Theme::Base.new
    drop = Taski::Progress::Layout::ThemeDrop.new(theme_obj)

    liquid_template = Liquid::Template.parse("{{ items | truncate_list: 3 }}", environment: @environment)
    result = liquid_template.render("items" => %w[A B C D E], "template" => drop)

    assert_equal "A, B, C...", result
  end

  def test_truncate_list_without_truncation
    theme_obj = Taski::Progress::Theme::Base.new
    drop = Taski::Progress::Layout::ThemeDrop.new(theme_obj)

    liquid_template = Liquid::Template.parse("{{ items | truncate_list: 3 }}", environment: @environment)
    result = liquid_template.render("items" => %w[A B], "template" => drop)

    assert_equal "A, B", result
  end

  def test_truncate_list_exact_limit
    theme_obj = Taski::Progress::Theme::Base.new
    drop = Taski::Progress::Layout::ThemeDrop.new(theme_obj)

    liquid_template = Liquid::Template.parse("{{ items | truncate_list: 3 }}", environment: @environment)
    result = liquid_template.render("items" => %w[A B C], "template" => drop)

    assert_equal "A, B, C", result
  end

  def test_truncate_list_with_custom_separator_and_suffix
    custom_theme = Class.new(Taski::Progress::Theme::Base) do
      def truncate_list_separator
        " / "
      end

      def truncate_list_suffix
        " など"
      end
    end.new

    drop = Taski::Progress::Layout::ThemeDrop.new(custom_theme)

    liquid_template = Liquid::Template.parse("{{ items | truncate_list: 2 }}", environment: @environment)
    result = liquid_template.render("items" => %w[A B C D], "template" => drop)

    assert_equal "A / B など", result
  end

  def test_truncate_list_with_nil
    liquid_template = Liquid::Template.parse("{{ items | truncate_list: 3 }}", environment: @environment)
    result = liquid_template.render("items" => nil)

    assert_equal "", result
  end

  def test_truncate_list_with_empty_array
    liquid_template = Liquid::Template.parse("{{ items | truncate_list: 3 }}", environment: @environment)
    result = liquid_template.render("items" => [])

    assert_equal "", result
  end

  # === truncate_text filter tests ===

  def test_truncate_text_within_limit
    theme_obj = Taski::Progress::Theme::Base.new
    drop = Taski::Progress::Layout::ThemeDrop.new(theme_obj)

    liquid_template = Liquid::Template.parse("{{ text | truncate_text: 40 }}", environment: @environment)
    result = liquid_template.render("text" => "Short text", "template" => drop)

    assert_equal "Short text", result
  end

  def test_truncate_text_exceeds_limit
    theme_obj = Taski::Progress::Theme::Base.new
    drop = Taski::Progress::Layout::ThemeDrop.new(theme_obj)

    liquid_template = Liquid::Template.parse("{{ text | truncate_text: 20 }}", environment: @environment)
    result = liquid_template.render("text" => "This is a very long text that should be truncated", "template" => drop)

    assert_equal "This is a very lo...", result
  end

  def test_truncate_text_exact_limit
    theme_obj = Taski::Progress::Theme::Base.new
    drop = Taski::Progress::Layout::ThemeDrop.new(theme_obj)

    liquid_template = Liquid::Template.parse("{{ text | truncate_text: 10 }}", environment: @environment)
    result = liquid_template.render("text" => "0123456789", "template" => drop)

    assert_equal "0123456789", result
  end

  def test_truncate_text_with_nil
    liquid_template = Liquid::Template.parse("{{ text | truncate_text: 20 }}", environment: @environment)
    result = liquid_template.render("text" => nil)

    assert_equal "", result
  end

  def test_truncate_text_with_custom_suffix
    custom_theme = Class.new(Taski::Progress::Theme::Base) do
      def truncate_text_suffix
        "…"
      end
    end.new

    drop = Taski::Progress::Layout::ThemeDrop.new(custom_theme)

    liquid_template = Liquid::Template.parse("{{ text | truncate_text: 15 }}", environment: @environment)
    result = liquid_template.render("text" => "This is a long text to truncate", "template" => drop)

    assert_equal "This is a long…", result
  end

  def test_truncate_text_without_theme_drop_uses_default
    liquid_template = Liquid::Template.parse("{{ text | truncate_text: 15 }}", environment: @environment)
    result = liquid_template.render("text" => "This is a long text to truncate")

    assert_equal "This is a lo...", result
  end
end
