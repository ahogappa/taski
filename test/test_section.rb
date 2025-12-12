# frozen_string_literal: true

require_relative "test_helper"
require_relative "fixtures/parallel_tasks"

class TestSection < Minitest::Test
  def setup
    Taski::Task.reset!
  end

  def teardown
    Taski::Task.reset!
  end

  # Test that nested classes in Section inherit interfaces after execution
  def test_nested_class_inherits_interfaces
    # After Section execution, the implementation class has interface methods
    NestedSection.run
    assert_equal [:host, :port], NestedSection::LocalDB.exported_methods
  end

  # Test Section with nested implementation works end-to-end
  def test_section_with_nested_implementation
    NestedSection.run

    assert_equal "localhost", NestedSection.host
    assert_equal 5432, NestedSection.port
  end

  # Test that external implementations still work (traditional pattern)
  def test_section_with_external_implementation
    ExternalImplSection.run

    assert_equal "external implementation", ExternalImplSection.value
  end

  # Test external implementation requires explicit exports
  def test_external_impl_has_explicit_exports
    assert_equal [:value], ExternalImpl.exported_methods
  end
end
