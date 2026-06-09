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

  # A subclass that inherits exports without re-declaring them must still be able
  # to resolve those exports (exported_methods walks the ancestor chain).
  def test_subclass_inherits_parent_exports
    assert_equal "base-value", ReservedExportFixtures::InheritsExport.value
  end

  # A subclass that adds an export keeps the inherited ones too (merge, not clobber).
  def test_subclass_adding_an_export_keeps_inherited_exports
    assert_equal "base-value", ReservedExportFixtures::AddsExport.value
    assert_equal "extra-value", ReservedExportFixtures::AddsExport.extra
  end

  # A task depending on a subclass's inherited export resolves it through the
  # execution pipeline (public_send → instance method_missing).
  def test_dependent_task_can_read_subclass_inherited_export
    assert_equal "got: base-value", ReservedExportFixtures::ConsumesInherited.combined
  end

  # Collision detection must also catch already-defined PRIVATE methods: an
  # external `.secret` call reaches the export via method_missing while an
  # internal `secret` call hits the private method, so the name is ambiguous.
  def test_exports_warns_when_name_collides_with_a_private_method
    _out, err = capture_io do
      Class.new(Taski::Task) do
        def secret
          1
        end
        private :secret
        exports :secret
      end
    end
    assert_match(/secret/, err)
  end

  # A malformed accessor call (positional or unknown-keyword args) must fail fast
  # rather than silently resolving and dropping the args.
  def test_export_accessor_rejects_malformed_args
    assert_raises(NoMethodError) { ReservedExportFixtures::BaseExport.value(123) }
    assert_raises(NoMethodError) { ReservedExportFixtures::BaseExport.value(bogus: 1) }
  end

  # Multiple `exports` calls on the same class accumulate; an earlier export must
  # not be clobbered by a later one.
  def test_multiple_exports_calls_accumulate
    assert_equal "first-value", ReservedExportFixtures::TwiceExports.first
    assert_equal "second-value", ReservedExportFixtures::TwiceExports.second
  end

  # An export name passed as a String resolves the same as a Symbol — exports
  # must normalize, because method_missing always receives the name as a Symbol.
  def test_string_export_name_resolves
    assert_equal "string-export-value", ReservedExportFixtures::StringExport.strval
  end

  # The instance-level export reader takes no arguments; passing any must fail
  # fast (NoMethodError) rather than silently dropping them.
  def test_instance_export_reader_rejects_extra_args
    inst = TaskiTestHelper.build_task_instance(ReservedExportFixtures::BaseExport)
    assert_raises(NoMethodError) { inst.value(123) }
  end

  # Generic Kernel/Object private methods (format, gets, ...) are excluded from
  # collision detection, so exporting such a name must not warn.
  def test_exports_does_not_warn_for_generic_kernel_method_names
    _out, err = capture_io do
      Class.new(Taski::Task) { exports :format }
    end
    assert_empty err
  end
end
