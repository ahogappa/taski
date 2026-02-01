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

  # Test Section with nil impl does nothing
  def test_section_run_with_nil_impl_does_nothing
    section_class = Class.new(Taski::Section) do
      interfaces :value

      def impl
        nil
      end
    end

    # Should not raise an error
    section_class.run

    # Exported values should be nil
    assert_nil section_class.value
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

    # Run with args that selects OptionB
    LazyDependencyTest::MySection.run(args: {use_option_a: false})

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
    ImplDependsOnTaskTest::FinalTask.run(args: {fast_mode: true})

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

    # Final result should use FastImpl (use captured value, not class accessor)
    assert_equal "final: fast result", ImplDependsOnTaskTest.captured_output
  end

  def test_section_impl_depends_on_task_slow_mode
    ImplDependsOnTaskTest.reset

    # Run with fast_mode = false (default)
    ImplDependsOnTaskTest::FinalTask.run(args: {fast_mode: false})

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

    # Final result should use SlowImpl (use captured value, not class accessor)
    assert_equal "final: slow result with slow data", ImplDependsOnTaskTest.captured_output
  end

  # Test execution order: impl is called first, then blocks on ConditionTask
  # The impl method is called during Section.run, and when it accesses
  # ConditionTask.use_fast_mode, it blocks until ConditionTask completes.
  def test_section_impl_blocks_on_dependency
    ImplDependsOnTaskTest.reset

    ImplDependsOnTaskTest::ConditionalSection.run(args: {fast_mode: true})

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

  # ========================================
  # Section run_and_clean Tests
  # ========================================

  # Test that Section registers runtime dependency and implementation gets cleaned
  def test_section_run_and_clean_cleans_implementation
    require_relative "fixtures/section_clean_fixtures"

    SectionCleanFixtures.reset_all

    SectionCleanFixtures::MainTask.run_and_clean

    clean_order = SectionCleanFixtures::CleanOrder.order

    # MainTask depends on DatabaseSection which selects LocalDBImpl
    # Clean order should be: MainTask → DatabaseSection → LocalDBImpl
    assert_includes clean_order, :main_task, "MainTask should be cleaned"
    assert_includes clean_order, :database_section, "DatabaseSection should be cleaned"
    assert_includes clean_order, :local_db_impl, "LocalDBImpl (selected implementation) should be cleaned"

    # Verify reverse order: MainTask cleans first, then Section, then Impl
    main_idx = clean_order.index(:main_task)
    section_idx = clean_order.index(:database_section)
    impl_idx = clean_order.index(:local_db_impl)

    assert main_idx < section_idx, "MainTask (#{main_idx}) should clean before Section (#{section_idx})"
    assert section_idx < impl_idx, "Section (#{section_idx}) should clean before Impl (#{impl_idx})"
  end

  # Test that run_and_clean executes both run and clean for Section
  def test_section_run_and_clean_executes_both_phases
    require_relative "fixtures/section_clean_fixtures"

    SectionCleanFixtures.reset_all

    SectionCleanFixtures::DatabaseSection.run_and_clean

    run_order = SectionCleanFixtures::RunOrder.order
    clean_order = SectionCleanFixtures::CleanOrder.order

    # Run phase should execute Section and its impl
    assert_includes run_order, :database_section, "Section should be run"
    assert_includes run_order, :local_db_impl, "Impl should be run"

    # Clean phase should clean both
    assert_includes clean_order, :database_section, "Section should be cleaned"
    assert_includes clean_order, :local_db_impl, "Impl should be cleaned"

    # Verify the Section exported value is accessible
    assert_equal "localhost:5432", SectionCleanFixtures::DatabaseSection.connection_string
  end

  # Test that Section's clean is called even when impl returns nil
  def test_section_nil_impl_with_run_and_clean
    clean_called = false

    section_class = Class.new(Taski::Section) do
      interfaces :value

      def impl
        nil
      end

      define_method(:clean) do
        clean_called = true
      end
    end

    section_class.run_and_clean

    assert_nil section_class.value
    assert clean_called, "Section's clean should be called even when impl is nil"
  end

  # ========================================
  # Nested Executor Tests
  # ========================================

  # Test that Section's nested executor correctly handles pre-completed dependencies
  # This tests a critical scenario:
  # 1. ParentTask depends on SharedDependency and TestSection
  # 2. SharedDependency completes first (parallel execution)
  # 3. TestSection triggers a nested executor to run SectionImpl
  # 4. SectionImpl depends on SharedDependency (already completed)
  # 5. The nested executor must recognize SharedDependency as completed
  #    and not deadlock waiting for it
  def test_nested_executor_with_pre_completed_dependency
    require_relative "fixtures/nested_executor_fixtures"

    NestedExecutorFixtures.reset_all

    # This should complete without deadlock
    Timeout.timeout(5) do
      NestedExecutorFixtures::ParentTask.run
    end

    # Verify all tasks executed
    order = NestedExecutorFixtures::ExecutionOrder.order
    assert_includes order, :shared_dependency, "SharedDependency should execute"
    assert_includes order, :test_section, "TestSection should execute"
    assert_includes order, :section_impl, "SectionImpl should execute"
    assert_includes order, :parent_task, "ParentTask should execute"

    # Verify the final output is correct
    assert_equal "shared data + impl using: shared data",
      NestedExecutorFixtures::ParentTask.output
  end

  # Test that Section's nested executor correctly waits for RUNNING dependencies
  # This tests a critical race condition scenario:
  # 1. SlowSection and FastSection start running in parallel
  # 2. FastSection triggers a nested executor for DependsOnSlowSection
  # 3. DependsOnSlowSection depends on SlowSection which is still RUNNING
  # 4. The nested executor must WAIT for SlowSection to complete
  #    (not just check if completed, but actively wait)
  # This was the root cause of the Kompo2 deadlock bug.
  def test_nested_executor_waits_for_running_dependency
    require_relative "fixtures/nested_executor_fixtures"

    NestedExecutorFixtures.reset_all

    # Run in a separate thread so we can control timing
    result_thread = Thread.new do
      Timeout.timeout(5) do
        NestedExecutorFixtures::RaceConditionTask.run
      end
    end

    # Give time for tasks to start and reach the barrier
    sleep 0.1

    # At this point, SlowImpl should be running and waiting at the barrier
    # FastSection should be trying to run DependsOnSlowSection
    # which needs SlowSection to complete first
    order_before_release = NestedExecutorFixtures::ExecutionOrder.order
    assert_includes order_before_release, :slow_impl_start,
      "SlowImpl should have started"

    # Release the barrier to let SlowImpl complete
    NestedExecutorFixtures.slow_task_barrier.release

    # Wait for completion
    result_thread.join

    # Verify all tasks executed in correct order
    order = NestedExecutorFixtures::ExecutionOrder.order

    # SlowImpl must complete before DependsOnSlowSection can access its value
    slow_end_idx = order.index(:slow_impl_end)
    depends_end_idx = order.index(:depends_on_slow_end)

    assert slow_end_idx, "SlowImpl should complete"
    assert depends_end_idx, "DependsOnSlowSection should complete"
    assert slow_end_idx < depends_end_idx,
      "SlowImpl must complete before DependsOnSlowSection finishes " \
      "(slow_end=#{slow_end_idx}, depends_end=#{depends_end_idx})"

    # Verify the final output is correct
    assert_equal "/slow/path + using: /slow/path",
      NestedExecutorFixtures::RaceConditionTask.output
  end
end
