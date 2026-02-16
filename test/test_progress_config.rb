# frozen_string_literal: true

require_relative "test_helper"

class TestProgressConfig < Minitest::Test
  def setup
    Taski.reset_progress_display!
  end

  def teardown
    Taski.reset_progress_display!
  end

  # === Default values ===

  def test_default_layout_is_nil
    config = Taski::Progress::Config.new
    assert_nil config.layout
  end

  def test_default_theme_is_nil
    config = Taski::Progress::Config.new
    assert_nil config.theme
  end

  def test_default_output_is_nil
    config = Taski::Progress::Config.new
    assert_nil config.output
  end

  # === Setter/Getter ===

  def test_set_layout_class
    config = Taski::Progress::Config.new
    config.layout = Taski::Progress::Layout::Tree
    assert_equal Taski::Progress::Layout::Tree, config.layout
  end

  def test_set_theme_class
    config = Taski::Progress::Config.new
    config.theme = Taski::Progress::Theme::Detail
    assert_equal Taski::Progress::Theme::Detail, config.theme
  end

  def test_set_output
    config = Taski::Progress::Config.new
    io = StringIO.new
    config.output = io
    assert_equal io, config.output
  end

  def test_set_layout_to_nil
    config = Taski::Progress::Config.new
    config.layout = Taski::Progress::Layout::Tree
    config.layout = nil
    assert_nil config.layout
  end

  def test_set_theme_to_nil
    config = Taski::Progress::Config.new
    config.theme = Taski::Progress::Theme::Detail
    config.theme = nil
    assert_nil config.theme
  end

  # === Validation ===

  def test_layout_rejects_non_layout_class
    config = Taski::Progress::Config.new
    assert_raises(ArgumentError) { config.layout = String }
  end

  def test_theme_rejects_non_theme_class
    config = Taski::Progress::Config.new
    assert_raises(ArgumentError) { config.theme = String }
  end

  def test_layout_rejects_instance
    config = Taski::Progress::Config.new
    assert_raises(ArgumentError) { config.layout = Taski::Progress::Layout::Simple.new }
  end

  def test_theme_rejects_instance
    config = Taski::Progress::Config.new
    assert_raises(ArgumentError) { config.theme = Taski::Progress::Theme::Default.new }
  end

  # === Config#build ===

  def test_build_default_returns_simple_layout
    config = Taski::Progress::Config.new
    display = config.build
    assert_instance_of Taski::Progress::Layout::Simple, display
  end

  def test_build_with_layout_class
    config = Taski::Progress::Config.new
    config.layout = Taski::Progress::Layout::Log
    display = config.build
    assert_instance_of Taski::Progress::Layout::Log, display
  end

  def test_build_with_theme_class
    config = Taski::Progress::Config.new
    config.theme = Taski::Progress::Theme::Plain
    display = config.build
    assert_instance_of Taski::Progress::Layout::Simple, display
  end

  def test_build_with_layout_module_uses_for
    config = Taski::Progress::Config.new
    config.layout = Taski::Progress::Layout::Tree
    display = config.build
    # Non-TTY default ($stderr in test is not TTY), so Tree.for returns Event
    assert_instance_of Taski::Progress::Layout::Tree::Event, display
  end

  def test_build_with_layout_module_and_theme
    config = Taski::Progress::Config.new
    config.layout = Taski::Progress::Layout::Tree
    config.theme = Taski::Progress::Theme::Plain
    display = config.build
    assert_instance_of Taski::Progress::Layout::Tree::Event, display
  end

  def test_build_with_layout_class_still_works
    config = Taski::Progress::Config.new
    config.layout = Taski::Progress::Layout::Tree::Event
    display = config.build
    assert_instance_of Taski::Progress::Layout::Tree::Event, display
  end

  def test_build_with_output
    config = Taski::Progress::Config.new
    io = StringIO.new
    config.output = io
    display = config.build
    assert_instance_of Taski::Progress::Layout::Simple, display
  end

  # === Invalidation ===

  def test_setting_layout_invalidates_display
    config = Taski::Progress::Config.new
    display1 = config.build
    config.layout = Taski::Progress::Layout::Log
    display2 = config.build
    refute_same display1, display2
    assert_instance_of Taski::Progress::Layout::Log, display2
  end

  def test_setting_theme_invalidates_display
    config = Taski::Progress::Config.new
    display1 = config.build
    config.theme = Taski::Progress::Theme::Detail
    display2 = config.build
    refute_same display1, display2
  end

  # === Config#reset ===

  def test_reset_clears_all_settings
    config = Taski::Progress::Config.new
    config.layout = Taski::Progress::Layout::Tree
    config.theme = Taski::Progress::Theme::Detail
    config.output = StringIO.new
    config.reset
    assert_nil config.layout
    assert_nil config.theme
    assert_nil config.output
  end

  # === Taski.progress integration ===

  def test_taski_progress_returns_config
    assert_instance_of Taski::Progress::Config, Taski.progress
  end

  def test_taski_progress_returns_same_instance
    assert_same Taski.progress, Taski.progress
  end

  def test_taski_progress_display_builds_from_config
    display = Taski.progress_display
    assert_instance_of Taski::Progress::Layout::Simple, display
  end

  def test_taski_progress_display_caches_instance
    display1 = Taski.progress_display
    display2 = Taski.progress_display
    assert_same display1, display2
  end

  def test_config_change_rebuilds_display
    display1 = Taski.progress_display
    Taski.progress.layout = Taski::Progress::Layout::Log
    display2 = Taski.progress_display
    refute_same display1, display2
    assert_instance_of Taski::Progress::Layout::Log, display2
  end

  def test_taski_progress_display_setter_works
    custom = Taski::Progress::Layout::Log.new
    Taski.progress_display = custom
    assert_same custom, Taski.progress_display
  end

  def test_reset_progress_display_clears_display_and_config
    Taski.progress.layout = Taski::Progress::Layout::Tree
    Taski.reset_progress_display!
    assert_nil Taski.progress.layout
    display = Taski.progress_display
    assert_instance_of Taski::Progress::Layout::Simple, display
  end
end
