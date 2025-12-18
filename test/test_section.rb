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

  # Test Section.impl that depends on another task's value
  # Example: def impl = TaskA.value ? TaskB : TaskC
  def test_section_impl_depends_on_task_fast_mode
    ImplDependsOnTaskTest.reset

    # Run with fast_mode = true
    ImplDependsOnTaskTest::FinalTask.run(context: {fast_mode: true})

    executed = ImplDependsOnTaskTest.executed_tasks

    # ConditionTask must be executed (impl depends on it)
    assert_includes executed, :condition_task,
      "ConditionTask should be executed because impl depends on it"

    # impl should be called after ConditionTask
    assert_includes executed, :impl_called,
      "impl method should be called"

    # FastImpl should be executed (condition is true)
    assert_includes executed, :fast_impl,
      "FastImpl should be executed when fast_mode is true"

    # SlowImpl and SlowDependency should NOT be executed
    refute_includes executed, :slow_impl,
      "SlowImpl should NOT be executed when fast_mode is true"
    refute_includes executed, :slow_dependency,
      "SlowDependency should NOT be executed when fast_mode is true"

    # Final result should use FastImpl
    assert_equal "final: fast result", ImplDependsOnTaskTest::FinalTask.output
  end

  def test_section_impl_depends_on_task_slow_mode
    ImplDependsOnTaskTest.reset

    # Run with fast_mode = false (default)
    ImplDependsOnTaskTest::FinalTask.run(context: {fast_mode: false})

    executed = ImplDependsOnTaskTest.executed_tasks

    # ConditionTask must be executed (impl depends on it)
    assert_includes executed, :condition_task,
      "ConditionTask should be executed because impl depends on it"

    # impl should be called
    assert_includes executed, :impl_called,
      "impl method should be called"

    # SlowImpl and its dependency should be executed
    assert_includes executed, :slow_impl,
      "SlowImpl should be executed when fast_mode is false"
    assert_includes executed, :slow_dependency,
      "SlowDependency should be executed as SlowImpl's dependency"

    # FastImpl should NOT be executed
    refute_includes executed, :fast_impl,
      "FastImpl should NOT be executed when fast_mode is false"

    # Final result should use SlowImpl
    assert_equal "final: slow result with slow data", ImplDependsOnTaskTest::FinalTask.output
  end

  # Test execution order: impl is called first, then blocks on ConditionTask
  # The impl method is called during Section.run, and when it accesses
  # ConditionTask.use_fast_mode, it blocks until ConditionTask completes.
  def test_section_impl_blocks_on_dependency
    ImplDependsOnTaskTest.reset

    ImplDependsOnTaskTest::ConditionalSection.run(context: {fast_mode: true})

    executed = ImplDependsOnTaskTest.executed_tasks

    # Both should be recorded
    assert_includes executed, :condition_task, "ConditionTask should be executed"
    assert_includes executed, :impl_called, "impl should be called"

    # impl is called first (during Section.run), then it accesses ConditionTask.use_fast_mode
    # which triggers ConditionTask execution and blocks until it completes
    impl_idx = executed.index(:impl_called)
    condition_idx = executed.index(:condition_task)

    assert impl_idx < condition_idx,
      "impl (#{impl_idx}) is called first, then blocks on ConditionTask (#{condition_idx})"
  end
end
