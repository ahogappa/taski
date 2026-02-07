# frozen_string_literal: true

require "test_helper"
require "taski/test_helper"
require "taski/test_helper/minitest"

# Fixture tasks for testing the test helper
module TestHelperFixtures
  # A simple task with no dependencies
  class LeafTask < Taski::Task
    exports :value

    def run
      @value = "leaf_result"
    end
  end

  # A task that depends on LeafTask (direct dependency)
  class MiddleTask < Taski::Task
    exports :result

    def run
      @result = "middle_" + LeafTask.value
    end
  end

  # A task that depends on MiddleTask (MiddleTask is direct, LeafTask is indirect)
  class TopTask < Taski::Task
    exports :output

    def run
      @output = "top_" + MiddleTask.result
    end
  end

  # A task with multiple exports
  class MultiExportTask < Taski::Task
    exports :first, :second, :third

    def run
      @first = "first_value"
      @second = "second_value"
      @third = "third_value"
    end
  end

  # A task that depends on multiple tasks
  class MultiDependencyTask < Taski::Task
    exports :combined

    def run
      @combined = LeafTask.value + "_" + MultiExportTask.first
    end
  end
end

class TestTestHelper < Minitest::Test
  include Taski::TestHelper

  def setup
    Taski::TestHelper.reset_mocks!
    Taski::Task.reset!
  end

  def teardown
    Taski::TestHelper.reset_mocks!
  end

  # === T007: Test basic mock registration and retrieval ===
  def test_mock_task_registers_mock
    mock = mock_task(TestHelperFixtures::LeafTask, value: "mocked_value")

    assert_instance_of Taski::TestHelper::MockWrapper, mock
    assert_equal TestHelperFixtures::LeafTask, mock.task_class
    assert_equal({value: "mocked_value"}, mock.mock_values)
  end

  def test_mock_for_returns_registered_mock
    mock_task(TestHelperFixtures::LeafTask, value: "mocked")

    retrieved = Taski::TestHelper.mock_for(TestHelperFixtures::LeafTask)
    assert_instance_of Taski::TestHelper::MockWrapper, retrieved
  end

  def test_mock_for_returns_nil_for_unregistered_task
    assert_nil Taski::TestHelper.mock_for(TestHelperFixtures::LeafTask)
  end

  def test_mocks_active_returns_true_when_mocks_registered
    refute Taski::TestHelper.mocks_active?

    mock_task(TestHelperFixtures::LeafTask, value: "mocked")

    assert Taski::TestHelper.mocks_active?
  end

  # === T008: Test mocked task returns configured value ===
  def test_mocked_task_returns_mock_value
    mock_task(TestHelperFixtures::LeafTask, value: "mocked_leaf")

    result = TestHelperFixtures::LeafTask.value

    assert_equal "mocked_leaf", result
  end

  def test_mocked_task_with_multiple_exports
    mock_task(TestHelperFixtures::MultiExportTask,
      first: "mock_first",
      second: "mock_second",
      third: "mock_third")

    assert_equal "mock_first", TestHelperFixtures::MultiExportTask.first
    assert_equal "mock_second", TestHelperFixtures::MultiExportTask.second
    assert_equal "mock_third", TestHelperFixtures::MultiExportTask.third
  end

  # === T009: Test mocked dependency task's run method is not executed ===
  def test_mocked_task_run_not_executed
    run_executed = false

    # Create a task class dynamically to track execution
    task_class = Class.new(Taski::Task) do
      exports :output

      define_method(:run) do
        run_executed = true
        @output = "real_output"
      end
    end

    mock_task(task_class, output: "mocked_output")
    result = task_class.output

    assert_equal "mocked_output", result
    refute run_executed, "run method should not have been executed"
  end

  # === T010: Test multiple direct dependencies can be mocked ===
  def test_multiple_dependencies_mocked
    mock_task(TestHelperFixtures::LeafTask, value: "mocked_leaf")
    mock_task(TestHelperFixtures::MultiExportTask, first: "mocked_first")

    result = TestHelperFixtures::MultiDependencyTask.combined

    assert_equal "mocked_leaf_mocked_first", result
  end

  # === T011: Test indirect dependencies are automatically isolated ===
  def test_indirect_dependencies_isolated
    leaf_run_executed = false
    original_run = TestHelperFixtures::LeafTask.instance_method(:run)

    # Temporarily replace LeafTask#run to track if it's called
    TestHelperFixtures::LeafTask.define_method(:run) do
      leaf_run_executed = true
      @value = "should_not_be_used"
    end

    begin
      # Mock only MiddleTask (direct dependency of TopTask)
      # LeafTask is indirect and should not run
      mock_task(TestHelperFixtures::MiddleTask, result: "mocked_middle")

      result = TestHelperFixtures::TopTask.output

      assert_equal "top_mocked_middle", result
      refute leaf_run_executed, "LeafTask (indirect dependency) should not have run"
    ensure
      TestHelperFixtures::LeafTask.define_method(:run, original_run)
    end
  end

  # === T012: Test mock value is returned consistently on multiple accesses ===
  def test_mock_value_consistent_on_multiple_accesses
    mock_task(TestHelperFixtures::LeafTask, value: "consistent_value")

    # Access multiple times
    result1 = TestHelperFixtures::LeafTask.value
    result2 = TestHelperFixtures::LeafTask.value
    result3 = TestHelperFixtures::LeafTask.value

    assert_equal "consistent_value", result1
    assert_equal "consistent_value", result2
    assert_equal "consistent_value", result3
  end

  # === T015: Test validation for task class (FR-012) ===
  def test_mock_invalid_task_class_raises_error
    error = assert_raises(Taski::TestHelper::InvalidTaskError) do
      mock_task(String, foo: "bar")
    end

    assert_match(/not a Taski::Task/, error.message)
    assert_match(/String/, error.message)
  end

  def test_mock_non_class_raises_error
    error = assert_raises(Taski::TestHelper::InvalidTaskError) do
      mock_task("not_a_class", foo: "bar")
    end

    assert_match(/not a Taski::Task/, error.message)
  end

  # === T016: Test validation for exported methods (FR-013) ===
  def test_mock_invalid_method_raises_error
    error = assert_raises(Taski::TestHelper::InvalidMethodError) do
      mock_task(TestHelperFixtures::LeafTask, nonexistent: "value")
    end

    assert_match(/not an exported method/, error.message)
    assert_match(/:nonexistent/, error.message)
    assert_match(/LeafTask/, error.message)
    assert_match(/\[:value\]/, error.message)
  end

  def test_mock_partial_invalid_methods_raises_error
    error = assert_raises(Taski::TestHelper::InvalidMethodError) do
      mock_task(TestHelperFixtures::MultiExportTask,
        first: "valid",
        invalid_method: "invalid")
    end

    assert_match(/:invalid_method/, error.message)
  end

  # === Additional tests for robustness ===
  def test_reset_mocks_clears_all_mocks
    mock_task(TestHelperFixtures::LeafTask, value: "mocked")
    assert Taski::TestHelper.mocks_active?

    Taski::TestHelper.reset_mocks!

    refute Taski::TestHelper.mocks_active?
    assert_nil Taski::TestHelper.mock_for(TestHelperFixtures::LeafTask)
  end

  def test_duplicate_mock_registration_overwrites
    mock_task(TestHelperFixtures::LeafTask, value: "first")
    mock_task(TestHelperFixtures::LeafTask, value: "second")

    result = TestHelperFixtures::LeafTask.value

    assert_equal "second", result
  end

  def test_mock_with_nil_value
    mock_task(TestHelperFixtures::LeafTask, value: nil)

    result = TestHelperFixtures::LeafTask.value

    assert_nil result
  end

  def test_mock_with_complex_value
    complex_value = {users: [1, 2, 3], metadata: {count: 3}}
    mock_task(TestHelperFixtures::LeafTask, value: complex_value)

    result = TestHelperFixtures::LeafTask.value

    assert_equal complex_value, result
    assert_equal [1, 2, 3], result[:users]
  end

  # === T017: Test access tracking records method calls ===
  def test_access_tracking_records_method_calls
    mock = mock_task(TestHelperFixtures::LeafTask, value: "test")

    refute mock.accessed?(:value)
    assert_equal 0, mock.access_count(:value)

    TestHelperFixtures::LeafTask.value

    assert mock.accessed?(:value)
    assert_equal 1, mock.access_count(:value)

    TestHelperFixtures::LeafTask.value
    TestHelperFixtures::LeafTask.value

    assert_equal 3, mock.access_count(:value)
  end

  # === T018: Test assert_task_accessed passes when method was accessed ===
  def test_assert_task_accessed_passes_when_accessed
    mock_task(TestHelperFixtures::LeafTask, value: "test")
    TestHelperFixtures::LeafTask.value

    # Should not raise
    assert_task_accessed(TestHelperFixtures::LeafTask, :value)
  end

  # === T019: Test assert_task_accessed fails when method was not accessed ===
  def test_assert_task_accessed_fails_when_not_accessed
    mock_task(TestHelperFixtures::LeafTask, value: "test")
    # Do NOT access the value

    error = assert_raises(::Minitest::Assertion) do
      assert_task_accessed(TestHelperFixtures::LeafTask, :value)
    end

    assert_match(/LeafTask/, error.message)
    assert_match(/value/, error.message)
    assert_match(/not/, error.message)
  end

  # === T020: Test refute_task_accessed passes when method was not accessed ===
  def test_refute_task_accessed_passes_when_not_accessed
    mock_task(TestHelperFixtures::LeafTask, value: "test")
    # Do NOT access the value

    # Should not raise
    refute_task_accessed(TestHelperFixtures::LeafTask, :value)
  end

  def test_refute_task_accessed_fails_when_accessed
    mock_task(TestHelperFixtures::LeafTask, value: "test")
    TestHelperFixtures::LeafTask.value

    error = assert_raises(::Minitest::Assertion) do
      refute_task_accessed(TestHelperFixtures::LeafTask, :value)
    end

    assert_match(/LeafTask/, error.message)
    assert_match(/value/, error.message)
    assert_match(/1 time/, error.message)
  end

  def test_assert_task_accessed_raises_when_task_not_mocked
    error = assert_raises(ArgumentError) do
      assert_task_accessed(TestHelperFixtures::LeafTask, :value)
    end

    assert_match(/not mocked/, error.message)
  end

  def test_refute_task_accessed_raises_when_task_not_mocked
    error = assert_raises(ArgumentError) do
      refute_task_accessed(TestHelperFixtures::LeafTask, :value)
    end

    assert_match(/not mocked/, error.message)
  end
end

# === T025-T027: Test Minitest integration ===
class TestMinitestIntegration < Minitest::Test
  include Taski::TestHelper::Minitest

  # Test that mock_task is available via the module
  def test_minitest_module_includes_helper_methods
    assert respond_to?(:mock_task)
    assert respond_to?(:assert_task_accessed)
    assert respond_to?(:refute_task_accessed)
  end

  # Test automatic cleanup - this test should start with no mocks
  def test_automatic_cleanup_after_test
    # If setup worked, there should be no mocks
    refute Taski::TestHelper.mocks_active?

    # Create a mock
    mock_task(TestHelperFixtures::LeafTask, value: "test")
    assert Taski::TestHelper.mocks_active?

    # Mock will be cleaned up in teardown
  end

  # This test runs after the previous one and verifies cleanup happened
  def test_cleanup_occurred_from_previous_test
    # Mocks from previous test should be cleaned up
    refute Taski::TestHelper.mocks_active?
  end
end

# Test cleanup on test failure
class TestCleanupOnFailure < Minitest::Test
  include Taski::TestHelper::Minitest

  def setup
    super
    @mock_was_cleaned = !Taski::TestHelper.mocks_active?
  end

  def test_cleanup_occurs_even_with_setup_state
    # This verifies setup ran and cleaned mocks
    assert @mock_was_cleaned, "setup should have cleaned mocks"

    # Create a mock
    mock_task(TestHelperFixtures::LeafTask, value: "test")
    assert Taski::TestHelper.mocks_active?
  end
end

# === T036: Test thread safety ===
class TestThreadSafety < Minitest::Test
  include Taski::TestHelper

  def setup
    Taski::TestHelper.reset_mocks!
    Taski::Task.reset!
  end

  def teardown
    Taski::TestHelper.reset_mocks!
  end

  def test_mocks_work_across_worker_threads
    # This tests that mocks registered in the main thread
    # are accessible from worker threads during task execution
    mock_task(TestHelperFixtures::LeafTask, value: "thread_safe_value")

    # Execute task with workers (uses thread pool)
    result = TestHelperFixtures::MiddleTask.result

    assert_equal "middle_thread_safe_value", result
  end

  def test_concurrent_mock_registration_is_safe
    # Test that registering mocks concurrently doesn't cause issues
    threads = 10.times.map do |i|
      Thread.new do
        task_class = Class.new(Taski::Task) do
          exports :value
          define_method(:run) { @value = "thread_#{i}" }
        end
        mock_task(task_class, value: "mocked_#{i}")
      end
    end

    threads.each(&:join)

    # All mocks should be registered
    assert Taski::TestHelper.mocks_active?
  end
end

# === T032-T034: Test Selective Mocking (US4) ===
class TestSelectiveMocking < Minitest::Test
  include Taski::TestHelper

  def setup
    Taski::TestHelper.reset_mocks!
    Taski::Task.reset!
  end

  def teardown
    Taski::TestHelper.reset_mocks!
  end

  # T032: Test unmocked dependencies execute normally
  def test_unmocked_dependencies_execute_normally
    # Do not mock LeafTask - it should run normally
    result = TestHelperFixtures::LeafTask.value

    assert_equal "leaf_result", result
  end

  # T033: Test mixed mocked and unmocked dependencies work together
  def test_mixed_mocked_and_unmocked_dependencies
    # Mock only LeafTask, let MultiExportTask run normally
    mock_task(TestHelperFixtures::LeafTask, value: "mocked_leaf")
    # MultiExportTask is NOT mocked

    result = TestHelperFixtures::MultiDependencyTask.combined

    # LeafTask returns mocked value, MultiExportTask runs normally
    assert_equal "mocked_leaf_first_value", result
  end

  # T034: Test mock lookup returns nil for unmocked tasks
  def test_mock_lookup_returns_nil_for_unmocked
    mock_task(TestHelperFixtures::LeafTask, value: "mocked")

    # LeafTask is mocked
    refute_nil Taski::TestHelper.mock_for(TestHelperFixtures::LeafTask)

    # MultiExportTask is NOT mocked
    assert_nil Taski::TestHelper.mock_for(TestHelperFixtures::MultiExportTask)
  end
end
