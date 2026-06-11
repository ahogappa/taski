# frozen_string_literal: true

require_relative "test_helper"
require "json"
require "stringio"
require "tempfile"
require "pathname"

# Data themes (Theme::Declarative): inert YAML loaded via Theme.load /
# Theme.from_hash into an anonymous Theme::Base subclass. Fail-fast contract:
# everything that can be wrong with a theme file raises Theme::LoadError at
# load time with the offending key in the message — a theme that loads cannot
# fail at render time.
class TestThemeDeclarative < Minitest::Test
  THEME = Taski::Progress::Theme
  FIXTURES = File.expand_path("fixtures/themes", __dir__)

  def task_info(**fields) = Taski::Progress::TaskInfo.new(**fields)

  def execution_info(**fields) = Taski::Progress::ExecutionInfo.new(**fields)

  # === Happy path ===

  def test_from_hash_returns_theme_base_subclass_with_zero_arg_new
    klass = THEME.from_hash({"templates" => {"task_start" => "GO %{name}"}})
    assert_operator klass, :<=, THEME::Base
    theme = klass.new
    assert_equal "GO MyTask", theme.task_start(task: task_info(name: "A::MyTask"))
  end

  def test_load_reads_yaml_file
    with_theme_file(<<~YAML) do |path|
      templates:
        task_start: "GO %{name}"
    YAML
      theme = THEME.load(path).new
      assert_equal "GO MyTask", theme.task_start(task: task_info(name: "A::MyTask"))
    end
  end

  def test_undeclared_templates_fall_back_to_extends_theme
    klass = THEME.from_hash({
      "extends" => "compact",
      "templates" => {"task_start" => "GO %{name}"}
    })
    theme = klass.new
    # execution_running comes from Compact (spinner + [done/total])
    out = theme.execution_running(execution: execution_info(done_count: 3, total_count: 5, spinner_index: 0))
    assert_equal "⠋ [3/5]", out
  end

  def test_default_extends_is_default_theme
    klass = THEME.from_hash({})
    assert_operator klass, :<=, THEME::Default,
      "with no extends, the loaded theme must inherit from Default"
    assert_equal "[START] MyTask", klass.new.task_start(task: task_info(name: "MyTask"))
  end

  def test_from_hash_accepts_symbol_keys
    klass = THEME.from_hash({
      schema: 1,
      extends: "detail",
      icons: {success: "🎉"},
      templates: {task_start: "GO %{name}"}
    })
    theme = klass.new
    assert_equal "GO T", theme.task_start(task: task_info(name: "T"))
    assert_equal "🎉", theme.icon_success
  end

  def test_from_hash_symbol_keys_do_not_bypass_validation
    assert_raises(THEME::LoadError) { THEME.from_hash({schema: 99}) }
    assert_raises(THEME::LoadError) { THEME.from_hash({templats: {}}) }
    assert_raises(THEME::LoadError) { THEME.from_hash({templates: {task_strat: "x"}}) }
  end

  # === Declared config applies to FALLBACK-rendered templates too ===
  # The loaded class really inherits from the extends theme, so a colors-only
  # or icons-only theme styles every line — same semantics as a Ruby subclass.

  def test_declared_colors_apply_to_fallback_rendered_templates
    klass = THEME.from_hash({
      "extends" => "detail",
      "colors" => {"green" => "<G>", "reset" => "<R>"}
    })
    theme = klass.new
    # task_success is NOT declared — Detail renders it, with the YAML colors
    out = theme.task_success(task: task_info(name: "T", state: :completed, duration: 123))
    assert_equal "<G>✓<R> T (123ms)", out
  end

  def test_declared_icons_apply_to_fallback_rendered_templates
    klass = THEME.from_hash({
      "extends" => "detail",
      "icons" => {"success" => "🎉"},
      "colors" => {"green" => "", "reset" => ""}
    })
    out = klass.new.task_success(task: task_info(name: "T", state: :completed))
    assert_equal "🎉 T", out
  end

  def test_declared_spinner_frames_apply_to_fallback_rendered_templates
    # No spinner split-brain: the fallback-rendered Detail#task_start must use
    # the YAML frames, consistently with the layout timer's modulo.
    klass = THEME.from_hash({
      "extends" => "detail",
      "spinner" => {"frames" => ["A", "B"]}
    })
    theme = klass.new
    out = theme.task_start(task: task_info(name: "T"), execution: execution_info(spinner_index: 1))
    assert_equal "B T", out
  end

  def test_declared_fragments_apply_to_fallback_rendered_templates
    klass = THEME.from_hash({"fragments" => {"duration_part" => " [%{duration}]"}})
    # task_success is undeclared — Default renders it through our fragment
    out = klass.new.task_success(task: task_info(name: "T", duration: 123))
    assert_equal "[DONE] T [123ms]", out
  end

  # === Placeholder vocabulary ===

  def test_color_placeholders_resolve_theme_colors
    klass = THEME.from_hash({
      "colors" => {"green" => "<G>", "reset" => "<R>"},
      "templates" => {"task_success" => "%{green}%{name}%{reset}"}
    })
    assert_equal "<G>T<R>", klass.new.task_success(task: task_info(name: "T"))
  end

  def test_icon_placeholder_uses_task_state_for_task_templates
    klass = THEME.from_hash({"templates" => {"task_success" => "%{icon} %{name}"}})
    out = klass.new.task_success(task: task_info(name: "T", state: :completed))
    assert_equal "\e[32m✓\e[0m T", out
  end

  def test_icon_placeholder_uses_execution_state_for_execution_templates
    klass = THEME.from_hash({"templates" => {"execution_fail" => "%{icon} ng"}})
    out = klass.new.execution_fail(execution: execution_info(state: :failed))
    assert_equal "\e[31m✗\e[0m ng", out
  end

  def test_spinner_placeholder_resolves_spinner_index
    klass = THEME.from_hash({"templates" => {"execution_running" => "%{spinner}"}})
    theme = klass.new
    assert_equal "⠸", theme.execution_running(execution: execution_info(spinner_index: 3))
  end

  def test_literal_percent_escaped_as_double_percent
    klass = THEME.from_hash({"templates" => {"task_start" => "%{name} 100%% done"}})
    assert_equal "T 100% done", klass.new.task_start(task: task_info(name: "T"))
  end

  def test_counts_route_through_format_count
    klass = THEME.from_hash({
      "formats" => {"count" => "%{count}件"},
      "templates" => {"execution_running" => "%{done_count}/%{total_count}"}
    })
    out = klass.new.execution_running(execution: execution_info(done_count: 3, total_count: 5))
    assert_equal "3件/5件", out
  end

  def test_duration_format_strings_cover_both_branches
    klass = THEME.from_hash({"formats" => {"duration_ms" => "%{ms}ミリ秒", "duration_s" => "%{s}秒"}})
    theme = klass.new
    assert_equal "123ミリ秒", theme.format_duration(123)
    assert_equal "1.2秒", theme.format_duration(1234)
    assert_equal "", theme.format_duration(nil)
  end

  def test_format_duration_switches_to_seconds_at_exactly_1000ms
    klass = THEME.from_hash({"formats" => {"duration_ms" => "%{ms}ms!", "duration_s" => "%{s}s!"}})
    theme = klass.new
    assert_equal "999ms!", theme.format_duration(999)
    assert_equal "1.0s!", theme.format_duration(1000)
  end

  # === Config values: declared wins, "" survives, else fallback ===

  def test_declared_empty_color_survives_and_does_not_fall_back
    klass = THEME.from_hash({"colors" => {"green" => ""}})
    theme = klass.new
    assert_equal "", theme.color_green
    # undeclared color falls back to the extends theme (Default ANSI)
    assert_equal "\e[31m", theme.color_red
  end

  def test_icons_spinner_and_intervals_come_from_definition
    klass = THEME.from_hash({
      "icons" => {"success" => "🎉"},
      "spinner" => {"frames" => ["A", "B"], "interval" => 0.5},
      "render_interval" => 0.25
    })
    theme = klass.new
    assert_equal "🎉", theme.icon_success
    assert_equal "✗", theme.icon_failure
    assert_equal ["A", "B"], theme.spinner_frames
    assert_in_delta 0.5, theme.spinner_interval
    assert_in_delta 0.25, theme.render_interval
    assert_equal "B", theme.spinner_frame(1)
  end

  def test_truncation_knobs_honored_by_parts
    klass = THEME.from_hash({
      "truncation" => {"list_limit" => 2, "list_suffix" => "…", "text_max" => 10, "text_suffix" => "…"}
    })
    theme = klass.new
    assert_equal " T1, T2…", theme.task_names_part(%w[A::T1 B::T2 C::T3])
    assert_equal " | 123456789…", theme.stdout_part("123456789012345")
  end

  # === Fragments: wrapper string is data, presence guard is engine-fixed ===

  def test_fragment_wrappers_are_data_with_color_placeholders
    klass = THEME.from_hash({
      "fragments" => {"duration_part" => " %{dim}(%{duration})%{reset}"},
      "colors" => {"dim" => "<D>", "reset" => "<R>"}
    })
    theme = klass.new
    assert_equal " <D>(123ms)<R>", theme.duration_part(123)
    assert_equal "", theme.duration_part(nil), "nil guard is engine-fixed, not overridable"
  end

  def test_fragment_presence_guards_are_engine_fixed
    klass = THEME.from_hash({"fragments" => {"error_part" => "!!%{error_message}!!"}})
    theme = klass.new
    assert_equal "!!boom!!", theme.error_part("boom")
    assert_equal "", theme.error_part(nil)
    assert_equal "", theme.error_part("")
  end

  # === Fail-fast load validation ===

  def test_unknown_top_level_key_raises
    error = assert_raises(THEME::LoadError) { THEME.from_hash({"templats" => {}}) }
    assert_includes error.message, "templats"
    assert_includes error.message, "allowed:"
  end

  def test_unknown_template_key_raises
    error = assert_raises(THEME::LoadError) { THEME.from_hash({"templates" => {"task_strat" => "x"}}) }
    assert_includes error.message, "task_strat"
  end

  def test_unknown_section_keys_raise
    assert_raises(THEME::LoadError) { THEME.from_hash({"icons" => {"sucess" => "x"}}) }
    assert_raises(THEME::LoadError) { THEME.from_hash({"colors" => {"blue" => "x"}}) }
    assert_raises(THEME::LoadError) { THEME.from_hash({"fragments" => {"durtion_part" => "x"}}) }
    assert_raises(THEME::LoadError) { THEME.from_hash({"truncation" => {"limit" => 3}}) }
  end

  def test_unknown_placeholder_raises_naming_the_template
    error = assert_raises(THEME::LoadError) do
      THEME.from_hash({"templates" => {"task_success" => "%{nope}"}})
    end
    assert_includes error.message, "templates.task_success"
  end

  def test_unknown_placeholder_in_fragment_raises_naming_the_fragment
    error = assert_raises(THEME::LoadError) do
      THEME.from_hash({"fragments" => {"error_part" => ": %{nope}"}})
    end
    assert_includes error.message, "fragments.error_part"
  end

  def test_stray_percent_forms_rejected
    ["100%", "%s", "%d", "%{name", "%<name>s"].each do |bad|
      error = assert_raises(THEME::LoadError, "expected #{bad.inspect} to be rejected") do
        THEME.from_hash({"templates" => {"task_start" => bad}})
      end
      assert_includes error.message, "stray %"
    end
  end

  def test_unsupported_schema_version_raises
    error = assert_raises(THEME::LoadError) { THEME.from_hash({"schema" => 2}) }
    assert_includes error.message, "schema version 2"
    assert_raises(THEME::LoadError) { THEME.from_hash({"schema" => "1"}) }
    assert_raises(THEME::LoadError) { THEME.from_hash({"schema" => 0}) }
    assert_raises(THEME::LoadError) { THEME.from_hash({"schema" => -1}) }
  end

  def test_schema_is_checked_before_unknown_keys
    # A future-schema file must fail with the forward-compat message, not
    # with whatever unknown key it happens to contain.
    error = assert_raises(THEME::LoadError) do
      THEME.from_hash({"schema" => 2, "future_section" => {}})
    end
    assert_includes error.message, "schema version 2"
  end

  def test_unknown_extends_raises
    error = assert_raises(THEME::LoadError) { THEME.from_hash({"extends" => "fancy"}) }
    assert_includes error.message, "fancy"
  end

  def test_type_errors_raise
    assert_raises(THEME::LoadError) { THEME.from_hash({"templates" => {"task_start" => 1}}) }
    assert_raises(THEME::LoadError) { THEME.from_hash({"spinner" => {"frames" => "abc"}}) }
    assert_raises(THEME::LoadError) { THEME.from_hash({"spinner" => {"interval" => -1}}) }
    assert_raises(THEME::LoadError) { THEME.from_hash({"render_interval" => 0}) }
    assert_raises(THEME::LoadError) { THEME.from_hash({"truncation" => {"list_limit" => "three"}}) }
    assert_raises(THEME::LoadError) { THEME.from_hash({"name" => 42}) }
  end

  def test_intervals_must_be_finite_and_bounded
    # .inf parses to Float::INFINITY — accepting it would kill the spinner /
    # render threads with RangeError from sleep and abort on_stop teardown
    # (hidden cursor, lost queued messages). Tiny values busy-loop the CPU.
    [Float::INFINITY, 1.0e20, 0.0001, 61].each do |bad|
      error = assert_raises(THEME::LoadError, "expected interval #{bad} rejected") do
        THEME.from_hash({"spinner" => {"interval" => bad}})
      end
      assert_includes error.message, "spinner.interval"
      assert_raises(THEME::LoadError) { THEME.from_hash({"render_interval" => bad}) }
    end
    # sane values still load
    theme = THEME.from_hash({"spinner" => {"interval" => 0.05}, "render_interval" => 1}).new
    assert_in_delta 0.05, theme.spinner_interval
    assert_in_delta 1, theme.render_interval
  end

  def test_truncation_integers_must_be_positive
    [0, -1].each do |bad|
      error = assert_raises(THEME::LoadError) { THEME.from_hash({"truncation" => {"list_limit" => bad}}) }
      assert_includes error.message, "truncation.list_limit"
      error = assert_raises(THEME::LoadError) { THEME.from_hash({"truncation" => {"text_max" => bad}}) }
      assert_includes error.message, "truncation.text_max"
    end
  end

  def test_non_mapping_top_level_raises
    assert_raises(THEME::LoadError) { THEME.from_hash(nil) }
    assert_raises(THEME::LoadError) { THEME.from_hash([1, 2]) }
  end

  def test_missing_file_raises_load_error
    error = assert_raises(THEME::LoadError) { THEME.load("/no/such/theme.yml") }
    assert_includes error.message, "/no/such/theme.yml"
  end

  def test_invalid_yaml_raises_load_error
    with_theme_file("templates: [unclosed") do |path|
      error = assert_raises(THEME::LoadError) { THEME.load(path) }
      assert_includes error.message, "invalid YAML"
    end
  end

  def test_yaml_aliases_raise_load_error_naming_the_file
    # safe_load_file raises Psych::AliasesNotEnabled for anchors/aliases —
    # it must surface as LoadError (the documented contract), not raw Psych.
    with_theme_file(<<~YAML) do |path|
      colors:
        green: &g "\\e[32m"
        dim: *g
    YAML
      error = assert_raises(THEME::LoadError) { THEME.load(path) }
      assert_includes error.message, File.basename(path)
    end
  end

  def test_yaml_date_scalars_raise_load_error
    # Unquoted dates resolve to Date, which safe_load_file disallows
    # (Psych::DisallowedClass) — must be wrapped as LoadError too.
    with_theme_file("name: 2026-06-11\n") do |path|
      assert_raises(THEME::LoadError) { THEME.load(path) }
    end
  end

  def test_empty_file_raises_load_error
    with_theme_file("") do |path|
      assert_raises(THEME::LoadError) { THEME.load(path) }
    end
  end

  def test_declarative_module_cannot_be_used_as_a_theme
    # Declarative is the factory namespace, not a theme class — assigning it
    # fails at assignment time (it is not a Class <= Theme::Base).
    config = Taski::Progress::Config.new
    assert_raises(ArgumentError) { config.theme = THEME::Declarative }
  end

  # === Byte-parity: YAML re-encodings of the 4 shipped themes reproduce the
  # === Liquid-era baseline exactly, through the data-theme pipeline ===

  def test_yaml_encoded_shipped_themes_match_liquid_baseline
    baseline = JSON.parse(File.read(File.expand_path("fixtures/theme_parity_baseline.json", __dir__)))
    themes = %w[default detail compact plain].to_h do |name|
      [name, THEME.load(File.join(FIXTURES, "#{name}.yml")).new]
    end

    baseline.fetch("cases").each do |c|
      theme = themes.fetch(c["theme"])
      t = c["task"]
      task = t && task_info(
        name: t["name"], state: t["state"]&.to_sym, duration: t["duration"],
        error_message: t["error_message"], group_name: t["group_name"], stdout: t["stdout"]
      )
      e = c.fetch("execution")
      execution = execution_info(
        state: e["state"]&.to_sym, pending_count: e["pending_count"],
        done_count: e["done_count"], completed_count: e["completed_count"],
        failed_count: e["failed_count"], skipped_count: e["skipped_count"],
        total_count: e["total_count"], total_duration: e["total_duration"],
        root_task_name: e["root_task_name"], task_names: e["task_names"],
        spinner_index: c["spinner_index"]
      )
      actual = theme.public_send(c["method"], task: task, execution: execution)
      assert_equal c["expected"], actual, "case #{c["id"]}: YAML data theme diverged from the Liquid baseline"
    end
  end

  def test_catppuccin_example_loads_and_renders_truecolor
    theme = THEME.load(File.expand_path("../examples/themes/catppuccin-mocha.yml", __dir__)).new
    out = theme.task_success(task: task_info(name: "A::Build", state: :completed, duration: 1234))
    assert_includes out, "\e[38;2;166;227;161m✔\e[0m", "truecolor success icon"
    assert_includes out, "\e[38;2;108;112;134m(1.2s)\e[0m", "dim duration fragment"
  end

  private

  def with_theme_file(content)
    Tempfile.create(["theme", ".yml"]) do |f|
      f.write(content)
      f.flush
      yield f.path
    end
  end
end

# Config integration: Taski.progress.theme = "path.yml" — validated at
# assignment, builds through the unchanged Class-contract, renders end to end
# through Layout::Log (observer events; no task execution involved).
class TestThemeDeclarativeConfig < Minitest::Test
  THEME = Taski::Progress::Theme

  def setup
    Taski.reset_progress_display!
  end

  def teardown
    Taski.reset_progress_display!
  end

  def test_config_accepts_string_path
    with_theme_file(<<~YAML) do |path|
      templates:
        task_start: "GO %{name}"
    YAML
      config = Taski::Progress::Config.new
      config.theme = path
      assert_operator config.theme, :<=, THEME::Base
    end
  end

  def test_config_accepts_pathname
    with_theme_file(<<~YAML) do |path|
      templates:
        task_start: "GO %{name}"
    YAML
      config = Taski::Progress::Config.new
      config.theme = Pathname.new(path)
      assert_operator config.theme, :<=, THEME::Base
    end
  end

  def test_config_raises_load_error_at_assignment_for_bad_path
    config = Taski::Progress::Config.new
    assert_raises(THEME::LoadError) { config.theme = "/no/such/theme.yml" }
    assert_nil config.theme, "a failed assignment must not change the config"
  end

  def test_config_raises_load_error_at_assignment_for_invalid_theme
    with_theme_file('templates: {task_start: "%{nope}"}') do |path|
      config = Taski::Progress::Config.new
      assert_raises(THEME::LoadError) { config.theme = path }
    end
  end

  def test_config_wraps_psych_level_errors_as_load_error
    # The documented contract: theme= raises Theme::LoadError at assignment —
    # including Psych errors beyond syntax (aliases, disallowed classes).
    with_theme_file("colors:\n  green: &g \"x\"\n  dim: *g\n") do |path|
      config = Taski::Progress::Config.new
      assert_raises(THEME::LoadError) { config.theme = path }
    end
  end

  def test_config_still_accepts_theme_classes
    config = Taski::Progress::Config.new
    config.theme = THEME::Detail
    assert_equal THEME::Detail, config.theme
  end

  def test_data_theme_renders_end_to_end_through_log_layout
    with_theme_file(<<~YAML) do |path|
      templates:
        task_start:   ">> %{name}"
        task_success: "OK %{name}%{duration_part}"
      fragments:
        duration_part: " [%{duration}]"
    YAML
      output = StringIO.new
      config = Taski::Progress::Config.new
      config.layout = Taski::Progress::Layout::Log
      config.theme = path
      config.output = output
      display = config.build

      task_class = Class.new
      task_class.define_singleton_method(:name) { "M::BuildTask" }
      now = Time.now
      display.on_start
      display.on_task_updated(task_class, previous_state: nil, current_state: :running, phase: :run, timestamp: now)
      display.on_task_updated(task_class, previous_state: :running, current_state: :completed, phase: :run, timestamp: now + 0.1)
      display.on_stop

      assert_includes output.string, ">> BuildTask"
      assert_match(/OK BuildTask \[\d+(\.\d+)?ms\]/, output.string)
    end
  end

  private

  def with_theme_file(content)
    Tempfile.create(["theme", ".yml"]) do |f|
      f.write(content)
      f.flush
      yield f.path
    end
  end
end
