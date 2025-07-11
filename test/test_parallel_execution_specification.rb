# frozen_string_literal: true

require_relative "test_helper"

class TestParallelExecutionSpecification < Minitest::Test
  def setup
    # Note: Task state reset would be handled individually in each test
    # since parallel execution tests create dynamic task classes
  end

  def teardown
    # Clean up all dynamically created constants
    cleanup_constants
    # Restore any mocked methods
    restore_mocked_methods
  end

  def test_parallel_execution_of_independent_tasks_in_dependency_graph
    skip "Parallel execution not implemented yet"

    execution_log = []

    task_a_class = Class.new(Taski::Task) do
      exports :result

      define_method(:run) do
        execution_log << [:start, :task_a, Time.now]
        sleep(0.1)
        @result = "TaskA result"
        execution_log << [:end, :task_a, Time.now]
      end
    end
    Object.const_set(:TaskA, task_a_class)

    task_b_class = Class.new(Taski::Task) do
      exports :result

      define_method(:run) do
        execution_log << [:start, :task_b, Time.now]
        sleep(0.1)
        @result = "TaskB result"
        execution_log << [:end, :task_b, Time.now]
      end
    end
    Object.const_set(:TaskB, task_b_class)

    root_task_class = Class.new(Taski::Task) do
      define_method(:run) do
        TaskA.result
        TaskB.result
        execution_log << [:start, :root_task, Time.now]
        execution_log << [:end, :root_task, Time.now]
      end
    end
    Object.const_set(:RootTask, root_task_class)

    start_time = Time.now
    RootTask.run_parallel
    end_time = Time.now

    assert (end_time - start_time) < 0.15, "Independent tasks should run in parallel"

    assert_includes execution_log.map { |entry| entry[1] }, :task_a
    assert_includes execution_log.map { |entry| entry[1] }, :task_b
    assert_includes execution_log.map { |entry| entry[1] }, :root_task
  end

  def test_dependent_tasks_wait_for_dependencies
    skip "Parallel execution not implemented yet"

    execution_order = []

    task_a_class = Class.new(Taski::Task) do
      exports :data

      define_method(:run) do
        execution_order << :task_a
        @data = "TaskA data"
      end
    end
    Object.const_set(:TaskA, task_a_class)

    task_b_class = Class.new(Taski::Task) do
      define_method(:run) do
        TaskA.data
        execution_order << :task_b
      end
    end
    Object.const_set(:TaskB, task_b_class)

    TaskB.run_parallel

    assert_equal [:task_a, :task_b], execution_order
  end

  def test_multiple_dependencies_all_completed_before_execution
    skip "Parallel execution not implemented yet"

    completion_tracker = {}
    execution_order = []

    task_a_class = Class.new(Taski::Task) do
      exports :value

      define_method(:run) do
        completion_tracker[:task_a] = Time.now
        execution_order << :task_a
        @value = "A"
      end
    end
    Object.const_set(:TaskA, task_a_class)

    task_b_class = Class.new(Taski::Task) do
      exports :value

      define_method(:run) do
        completion_tracker[:task_b] = Time.now
        execution_order << :task_b
        @value = "B"
      end
    end
    Object.const_set(:TaskB, task_b_class)

    task_c_class = Class.new(Taski::Task) do
      define_method(:run) do
        TaskA.value
        TaskB.value

        assert completion_tracker[:task_a], "TaskA should be completed before TaskC"
        assert completion_tracker[:task_b], "TaskB should be completed before TaskC"
        execution_order << :task_c
      end
    end
    Object.const_set(:TaskC, task_c_class)

    TaskC.run_parallel

    assert_equal 3, execution_order.size
    assert_equal :task_c, execution_order.last
    assert_includes execution_order, :task_a
    assert_includes execution_order, :task_b
  end

  def test_define_api_dependency_resolution
    skip "Parallel execution not implemented yet"

    execution_order = []

    task_a_class = Class.new(Taski::Task) do
      define :calculate do
        execution_order << :task_a_define
        42
      end
    end
    Object.const_set(:TaskA, task_a_class)

    task_b_class = Class.new(Taski::Task) do
      define_method(:run) do
        result = TaskA.calculate
        execution_order << :task_b
        result * 2
      end
    end
    Object.const_set(:TaskB, task_b_class)

    TaskB.run_parallel

    assert_equal [:task_a_define, :task_b], execution_order
  end

  # === Section特有の並列実行仕様 ===

  def test_section_dynamic_dependency_resolution
    skip "Parallel execution not implemented yet"

    execution_order = []
    condition = true

    task_a_class = Class.new(Taski::Task) do
      exports :result

      define_method(:run) do
        execution_order << :task_a
        @result = "TaskA result"
      end
    end
    Object.const_set(:TaskA, task_a_class)

    task_b_class = Class.new(Taski::Task) do
      exports :result

      define_method(:run) do
        execution_order << :task_b
        @result = "TaskB result"
      end
    end
    Object.const_set(:TaskB, task_b_class)

    section_class = Class.new(Taski::Section) do
      define_method(:impl) do
        condition ? TaskA : TaskB
      end
    end
    Object.const_set(:MySection, section_class)

    MySection.run_parallel

    assert_includes execution_order, :task_a
    refute_includes execution_order, :task_b
  end

  def test_section_waits_for_other_tasks_including_dependencies
    skip "Parallel execution not implemented yet"

    execution_order = []
    execution_times = {}

    other_task_class = Class.new(Taski::Task) do
      define_method(:run) do
        execution_times[:other_task_start] = Time.now
        execution_order << :other_task_start
        sleep(0.2)
        execution_order << :other_task_end
        execution_times[:other_task_end] = Time.now
      end
    end
    Object.const_set(:OtherTask, other_task_class)

    dependency_a_class = Class.new(Taski::Task) do
      exports :data

      define_method(:run) do
        execution_times[:dependency_a] = Time.now
        execution_order << :dependency_a
        sleep(0.1)
        @data = "A"
      end
    end
    Object.const_set(:DependencyA, dependency_a_class)

    dependency_b_class = Class.new(Taski::Task) do
      exports :data

      define_method(:run) do
        execution_times[:dependency_b] = Time.now
        execution_order << :dependency_b
        sleep(0.1)
        @data = "B"
      end
    end
    Object.const_set(:DependencyB, dependency_b_class)

    concrete_task_class = Class.new(Taski::Task) do
      define_method(:run) do
        DependencyA.data
        DependencyB.data
        execution_times[:concrete_task] = Time.now
        execution_order << :concrete_task
      end
    end
    Object.const_set(:ConcreteTask, concrete_task_class)

    section_class = Class.new(Taski::Section) do
      define_method(:impl) do
        ConcreteTask
      end

      define_method(:run) do
        execution_times[:section] = Time.now
        execution_order << :section
      end
    end
    Object.const_set(:MySection, section_class)

    Thread.new { OtherTask.run }
    sleep(0.05)

    MySection.run_parallel

    assert execution_times[:section] > execution_times[:other_task_end],
      "Section should wait until other tasks complete"

    assert execution_times[:dependency_a] > execution_times[:other_task_end],
      "Section dependencies should also wait until other tasks complete"
    assert execution_times[:dependency_b] > execution_times[:other_task_end],
      "Section dependencies should also wait until other tasks complete"

    dependency_a_time = execution_times[:dependency_a]
    dependency_b_time = execution_times[:dependency_b]
    time_diff = (dependency_a_time - dependency_b_time).abs

    assert time_diff < 0.05,
      "After other tasks complete, Section's dependencies should run in parallel"

    assert_includes execution_order, :dependency_a
    assert_includes execution_order, :dependency_b
    assert_includes execution_order, :concrete_task
    assert_includes execution_order, :section
    other_end_index = execution_order.index(:other_task_end)
    dep_a_index = execution_order.index(:dependency_a)
    dep_b_index = execution_order.index(:dependency_b)
    concrete_index = execution_order.index(:concrete_task)
    section_index = execution_order.index(:section)

    assert other_end_index < dep_a_index, "Dependencies should start after other tasks complete"
    assert other_end_index < dep_b_index, "Dependencies should start after other tasks complete"
    assert dep_a_index < concrete_index, "Dependencies should complete before concrete task"
    assert dep_b_index < concrete_index, "Dependencies should complete before concrete task"
    assert concrete_index < section_index, "Concrete task should complete before Section"
  end

  def test_multiple_sections_with_overlapping_dependencies
    skip "Parallel execution not implemented yet"

    execution_order = []

    shared_dependency_class = Class.new(Taski::Task) do
      exports :shared_data

      define_method(:run) do
        execution_order << :shared_dependency
        sleep(0.1)
        @shared_data = "shared value"
      end
    end
    Object.const_set(:SharedDependency, shared_dependency_class)

    # Section A の具象タスク
    concrete_task_a_class = Class.new(Taski::Task) do
      define_method(:run) do
        SharedDependency.shared_data
        execution_order << :concrete_task_a
      end
    end
    Object.const_set(:ConcreteTaskA, concrete_task_a_class)

    # Section B の具象タスク
    concrete_task_b_class = Class.new(Taski::Task) do
      define_method(:run) do
        SharedDependency.shared_data
        execution_order << :concrete_task_b
      end
    end
    Object.const_set(:ConcreteTaskB, concrete_task_b_class)

    section_a_class = Class.new(Taski::Section) do
      define_method(:impl) { ConcreteTaskA }
      define_method(:run) { execution_order << :section_a }
    end
    Object.const_set(:SectionA, section_a_class)

    section_b_class = Class.new(Taski::Section) do
      define_method(:impl) { ConcreteTaskB }
      define_method(:run) { execution_order << :section_b }
    end
    Object.const_set(:SectionB, section_b_class)

    root_task_class = Class.new(Taski::Task) do
      define_method(:run) do
        SectionA.run
        SectionB.run
      end
    end
    Object.const_set(:RootTask, root_task_class)

    RootTask.run_parallel

    shared_dependency_count = execution_order.count(:shared_dependency)
    assert_equal 1, shared_dependency_count,
      "Shared dependency should be executed only once"

    assert_includes execution_order, :concrete_task_a
    assert_includes execution_order, :concrete_task_b

    assert_includes execution_order, :section_a
    assert_includes execution_order, :section_b
    shared_index = execution_order.index(:shared_dependency)
    concrete_a_index = execution_order.index(:concrete_task_a)
    concrete_b_index = execution_order.index(:concrete_task_b)

    assert shared_index < concrete_a_index,
      "Shared dependency should complete before concrete tasks"
    assert shared_index < concrete_b_index,
      "Shared dependency should complete before concrete tasks"
  end

  # === スレッドセーフティ仕様 ===

  def test_concurrent_task_access_thread_safety
    skip "Parallel execution not implemented yet"

    access_count = 0
    mutex = Mutex.new

    shared_task_class = Class.new(Taski::Task) do
      exports :value

      define_method(:run) do
        mutex.synchronize { access_count += 1 }
        @value = "shared value"
      end
    end
    Object.const_set(:SharedTask, shared_task_class)

    # Note: dependent_tasksはTaskiでは通常、依存関係によって自動実行される
    # このテストはスレッドセーフティの検証のための特殊なケース
    root_task_class = Class.new(Taski::Task) do
      define_method(:run) do
        shared_task.value
      end
    end
    Object.const_set(:RootTask, root_task_class)

    RootTask.run_parallel

    assert_equal 1, access_count
  end

  def test_exports_api_thread_safety
    skip "Parallel execution not implemented yet"

    export_values = []
    mutex = Mutex.new

    producer_task_class = Class.new(Taski::Task) do
      exports :result

      define_method(:run) do
        @result = "produced value"
      end
    end
    Object.const_set(:ProducerTask, producer_task_class)

    root_task_class = Class.new(Taski::Task) do
      define_method(:run) do
        10.times do
          value = ProducerTask.result
          mutex.synchronize { export_values << value }
        end
      end
    end
    Object.const_set(:RootTask, root_task_class)

    RootTask.run_parallel

    assert_equal 10, export_values.size
    assert export_values.all? { |v| v == "produced value" }
  end

  # === エラーハンドリング仕様 ===

  def test_rescue_deps_works_in_parallel_execution
    skip "Parallel execution not implemented yet"

    execution_order = []

    failing_task_class = Class.new(Taski::Task) do
      exports :result

      define_method(:run) do
        execution_order << :failing_task
        raise "Task failure"
      end
    end
    Object.const_set(:FailingTask, failing_task_class)

    rescue_task_class = Class.new(Taski::Task) do
      rescue_deps FailingTask => ->(error) {
        execution_order << :rescue_handled
      }

      define_method(:run) do
        FailingTask.result
        execution_order << :rescue_task
      end
    end
    Object.const_set(:RescueTask, rescue_task_class)

    RescueTask.run_parallel

    assert_includes execution_order, :failing_task
    assert_includes execution_order, :rescue_handled
    assert_includes execution_order, :rescue_task
  end

  def test_root_task_error_terminates_all_running_tasks
    skip "Parallel execution not implemented yet"

    execution_order = []
    termination_flags = {task_a: false, task_b: false}

    long_running_task_a_class = Class.new(Taski::Task) do
      exports :result

      define_method(:run) do
        execution_order << :task_a_start
        begin
          sleep(5)
          @result = "TaskA result"
          execution_order << :task_a_complete
        rescue => e
          termination_flags[:task_a] = true
          execution_order << :task_a_terminated
          raise e
        end
      end
    end
    Object.const_set(:LongRunningTaskA, long_running_task_a_class)

    long_running_task_b_class = Class.new(Taski::Task) do
      exports :result

      define_method(:run) do
        execution_order << :task_b_start
        begin
          sleep(5)
          @result = "TaskB result"
          execution_order << :task_b_complete
        rescue => e
          termination_flags[:task_b] = true
          execution_order << :task_b_terminated
          raise e
        end
      end
    end
    Object.const_set(:LongRunningTaskB, long_running_task_b_class)

    failing_task_class = Class.new(Taski::Task) do
      define_method(:run) do
        sleep(0.1)
        execution_order << :failing_task
        raise "Root task error"
      end
    end
    Object.const_set(:FailingTask, failing_task_class)

    root_task_class = Class.new(Taski::Task) do
      define_method(:run) do
        LongRunningTaskA.result
        LongRunningTaskB.result
        FailingTask.run
        execution_order << :root_task
      end
    end
    Object.const_set(:RootTask, root_task_class)

    assert_raises(RuntimeError) do
      RootTask.run_parallel
    end

    assert_includes execution_order, :failing_task

    assert_includes execution_order, :task_a_start
    assert_includes execution_order, :task_b_start
    refute_includes execution_order, :task_a_complete
    refute_includes execution_order, :task_b_complete
    refute_includes execution_order, :root_task
  end

  def test_dependent_tasks_not_executed_when_dependency_fails
    skip "Parallel execution not implemented yet"

    execution_order = []

    failing_task_class = Class.new(Taski::Task) do
      exports :data

      define_method(:run) do
        execution_order << :failing_task
        raise "Dependency failure"
      end
    end
    Object.const_set(:FailingTask, failing_task_class)

    dependent_task_class = Class.new(Taski::Task) do
      define_method(:run) do
        FailingTask.data
        execution_order << :dependent_task
      end
    end
    Object.const_set(:DependentTask, dependent_task_class)

    assert_raises(RuntimeError) do
      DependentTask.run_parallel
    end

    assert_includes execution_order, :failing_task
    refute_includes execution_order, :dependent_task
  end

  # === パフォーマンス仕様 ===

  def test_parallel_execution_performance_improvement
    skip "Parallel execution not implemented yet"

    task_count = 4
    task_duration = 0.1

    tasks = task_count.times.map do |i|
      Class.new(Taski::Task) do
        exports :result

        define_method(:run) do
          sleep(task_duration)
          @result = "Task #{i} result"
        end
      end
    end

    task_classes = tasks.map.with_index do |task_class, i|
      Object.const_set("PerfTask#{i}", task_class)
      task_class
    end

    sequential_time = Benchmark.realtime do
      task_classes.each(&:run)
    end

    root_task_class = Class.new(Taski::Task) do
      define_method(:run) do
        task_classes.map(&:result)
      end
    end
    Object.const_set(:RootTask, root_task_class)

    parallel_time = Benchmark.realtime do
      RootTask.run_parallel
    end

    improvement_ratio = sequential_time / parallel_time
    assert improvement_ratio > 2.0, "Parallel execution should be significantly faster than sequential"
  end

  # === スレッド数制御仕様 ===

  def test_default_thread_count_uses_machine_processors
    skip "Parallel execution not implemented yet"

    require "etc"
    used_thread_count = nil

    @original_nprocessors = Etc.method(:nprocessors)
    Etc.define_singleton_method(:nprocessors) do
      8
    end

    task_class = Class.new(Taski::Task) do
      define_method(:run) do
        used_thread_count = Thread.current[:taski_max_threads]
      end
    end
    Object.const_set(:TestTask, task_class)

    TestTask.run_parallel

    assert_equal 8, used_thread_count
  end

  def test_explicit_thread_count_specification
    skip "Parallel execution not implemented yet"

    used_thread_count = nil

    task_class = Class.new(Taski::Task) do
      define_method(:run) do
        used_thread_count = Thread.current[:taski_max_threads]
      end
    end
    Object.const_set(:TestTask, task_class)

    TestTask.run_parallel(threads: 16)

    assert_equal 16, used_thread_count
  end

  def test_thread_count_with_other_arguments
    skip "Parallel execution not implemented yet"

    execution_data = []

    task_class = Class.new(Taski::Task) do
      define_method(:run) do
        execution_data << {
          threads: Thread.current[:taski_max_threads],
          args: run_args
        }
      end
    end
    Object.const_set(:TestTask, task_class)

    TestTask.run_parallel(threads: 4, test_param: "value")

    assert_equal 1, execution_data.size
    assert_equal 4, execution_data.first[:threads]
    assert_equal({test_param: "value"}, execution_data.first[:args])
  end

  # === パラメータ付き実行仕様 ===

  def test_parallel_execution_with_arguments
    skip "Parallel execution not implemented yet"

    execution_args = []

    task_with_args_class = Class.new(Taski::Task) do
      define_method(:run) do
        execution_args << run_args
      end
    end
    Object.const_set(:TaskWithArgs, task_with_args_class)

    TaskWithArgs.run_parallel(test_param: "parallel_value")

    assert_equal [{test_param: "parallel_value"}], execution_args
  end

  def test_dependent_task_with_arguments
    skip "Parallel execution not implemented yet"

    execution_data = []

    dependency_task_class = Class.new(Taski::Task) do
      exports :result

      define_method(:run) do
        execution_data << [:dependency, run_args]
        @result = "dependency result"
      end
    end
    Object.const_set(:DependencyTask, dependency_task_class)

    main_task_class = Class.new(Taski::Task) do
      define_method(:run) do
        DependencyTask.result
        execution_data << [:main, run_args]
      end
    end
    Object.const_set(:MainTask, main_task_class)

    MainTask.run_parallel(main_param: "main_value")

    # Note: DependencyTaskはrun中でパラメータを渡さないため空のハッシュ
    assert_equal 2, execution_data.size
    assert_includes execution_data, [:dependency, {}]
    assert_includes execution_data, [:main, {main_param: "main_value"}]
  end

  private

  def cleanup_constants
    test_constants = [
      :TaskA, :TaskB, :TaskC, :RootTask, :TestTask,
      :FailingTask, :DependentTask, :RescueTask,
      :LongRunningTaskA, :LongRunningTaskB,
      :ProducerTask, :SharedTask, :TaskWithArgs,
      :DependencyTask, :MainTask, :MySection,
      :OtherTask, :DependencyA, :DependencyB, :ConcreteTask,
      :SharedDependency, :ConcreteTaskA, :ConcreteTaskB,
      :SectionA, :SectionB
    ]

    (0..10).each do |i|
      test_constants << :"PerfTask#{i}"
    end

    test_constants.each do |const_name|
      Object.send(:remove_const, const_name) if Object.const_defined?(const_name)
    end
  end

  def restore_mocked_methods
    if instance_variable_defined?(:@original_nprocessors) && @original_nprocessors
      Etc.define_singleton_method(:nprocessors, &@original_nprocessors)
      @original_nprocessors = nil
    end
  end
end
