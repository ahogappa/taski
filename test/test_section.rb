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

  # Test Section#impl raises NotImplementedError when not overridden
  def test_section_impl_raises_not_implemented_error
    section_class = Class.new(Taski::Section) do
      interfaces :value
    end

    # Directly instantiate and call impl to test the error
    section_instance = section_class.allocate
    section_instance.send(:initialize)

    error = assert_raises(NotImplementedError) do
      section_instance.impl
    end
    assert_match(/Subclasses must implement the impl method/, error.message)
  end

  # Test Section with nil impl raises error in run
  def test_section_run_with_nil_impl_raises_error
    section_class = Class.new(Taski::Section) do
      interfaces :value

      def impl
        nil
      end
    end

    # Directly instantiate and call run to test the error
    section_instance = section_class.allocate
    section_instance.send(:initialize)

    error = assert_raises(RuntimeError) do
      section_instance.run
    end
    assert_match(/does not have an implementation/, error.message)
  end

  # Test nested Section (Section inside Section)
  # OuterSection uses InnerSection as impl, which is also a Section
  def test_nested_section_inside_section
    OuterSection.run

    # OuterSection should have the value from InnerSection
    assert_equal "postgres://localhost:5432/mydb", OuterSection.db_url

    # InnerSection should also be executed and have the same value
    assert_equal "postgres://localhost:5432/mydb", InnerSection.db_url
  end

  # Test that Section only executes dependencies of the selected implementation
  # When impl returns OptionB, OptionA's dependencies (ExpensiveTask) should NOT run
  def test_section_lazy_dependency_resolution
    LazyDependencyTest.reset

    # Run with context that selects OptionB
    LazyDependencyTest::MySection.run(context: {use_option_a: false})

    executed = LazyDependencyTest.executed_tasks

    # OptionB and its dependency (CheapTask) should be executed
    assert_includes executed, :option_b, "Selected implementation should be executed"
    assert_includes executed, :cheap_task, "Selected implementation's dependency should be executed"

    # ExpensiveTask should NOT be executed (it's only a dependency of OptionA)
    refute_includes executed, :expensive_task,
      "ExpensiveTask should NOT be executed when OptionA is not selected"

    # OptionA should NOT be executed
    refute_includes executed, :option_a,
      "OptionA should NOT be executed when OptionB is selected"

    # Value should be from OptionB
    assert_equal "B with cheap", LazyDependencyTest::MySection.value
  end
end
