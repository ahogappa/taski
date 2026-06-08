# frozen_string_literal: true

require "test_helper"
require_relative "fixtures/reserved_export_tasks"

class TestReservedExports < Minitest::Test
  def setup
    Taski::Task.reset! if defined?(Taski::Task)
  end

  # exports :name must not shadow Module#name in a way that breaks the framework.
  # Class.name should keep returning the real class name (used by static analysis,
  # logging, errors), not the export accessor.
  def test_exports_name_does_not_shadow_module_name
    klass = ReservedExportFixtures::ExportsName
    assert_equal "ReservedExportFixtures::ExportsName", klass.name
  end

  # Static analysis of a task that exports :name must not infinitely recurse.
  def test_exports_name_does_not_crash_static_analysis
    deps = nil
    Timeout.timeout(5) do
      deps = Taski::StaticAnalysis::Analyzer.analyze(ReservedExportFixtures::ExportsName)
    end
    assert_kind_of Enumerable, deps
  end

  # A task that exports :name must still be runnable.
  def test_exports_name_task_is_runnable
    Timeout.timeout(10) do
      ReservedExportFixtures::ExportsName.run(workers: 1)
    end
  end

  # Exporting a name that is already a defined method (so the accessor can't be
  # reached) must warn at definition time instead of silently shadowing it.
  def test_exports_warns_when_name_collides_with_existing_method
    _out, err = capture_io do
      Class.new(Taski::Task) { exports :name }
    end
    assert_match(/name/, err)
    assert_match(/exist/i, err)
  end

  # A non-colliding export name stays fully functional (no warning, reachable).
  def test_non_colliding_export_is_unaffected
    _out, err = capture_io do
      Class.new(Taski::Task) { exports :totally_custom_value }
    end
    assert_empty err
  end
end
