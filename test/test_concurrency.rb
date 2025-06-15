# frozen_string_literal: true

require_relative "test_helper"

class TestConcurrency < Minitest::Test
  include TaskiTestHelper

  def setup
    setup_taski_test
  end

  # === Performance and Concurrency Tests ===

  def test_thread_safety
    # Test thread safety of ensure_instance_built
    task = Class.new(Taski::Task) do
      exports :thread_id

      def build
        sleep 0.01 # Small delay to increase chance of race condition
        @thread_id = Thread.current.object_id
      end
    end
    Object.const_set(:ThreadSafeTask, task)

    # Run multiple threads trying to build simultaneously
    threads = 5.times.map do
      Thread.new { ThreadSafeTask.thread_id }
    end

    results = threads.map(&:value)

    # All threads should get the same instance (same thread_id)
    assert results.all? { |result| result == results.first }

    # Should only have one instance
    instance = ThreadSafeTask.instance_variable_get(:@__task_instance)
    refute_nil instance
  end

  def test_concurrent_task_building
    # Test multiple different tasks building concurrently
    task_x = Class.new(Taski::Task) do
      exports :x_value

      def build
        sleep 0.01
        @x_value = "X-#{Thread.current.object_id}"
      end
    end
    Object.const_set(:ConcurrentTaskX, task_x)

    task_y = Class.new(Taski::Task) do
      exports :y_value

      def build
        sleep 0.01
        @y_value = "Y-#{Thread.current.object_id}"
      end
    end
    Object.const_set(:ConcurrentTaskY, task_y)

    # Build both tasks concurrently
    threads = [
      Thread.new { ConcurrentTaskX.build },
      Thread.new { ConcurrentTaskY.build }
    ]

    threads.each(&:join)

    # Both should have built successfully
    assert_match(/^X-\d+$/, ConcurrentTaskX.x_value)
    assert_match(/^Y-\d+$/, ConcurrentTaskY.y_value)
  end

  def test_concurrent_access_to_same_task
    # Test concurrent access to the same task instance
    task = Class.new(Taski::Task) do
      exports :access_count

      def build
        @access_count = 0
      end

      def increment_count
        @access_count += 1
      end
    end
    Object.const_set(:SharedTask, task)

    # Build the task first
    SharedTask.build

    # Multiple threads accessing the same instance
    threads = 10.times.map do
      Thread.new do
        instance = SharedTask.instance_variable_get(:@__task_instance)
        instance.increment_count if instance
      end
    end

    threads.each(&:join)

    # Should have incremented 10 times
    # Note: This test may be flaky due to race conditions in increment_count
    # but it tests that the instance is shared correctly
    instance = SharedTask.instance_variable_get(:@__task_instance)
    assert_equal 10, instance.instance_variable_get(:@access_count)
  end

  def test_thread_local_recursion_detection
    # Test that thread-local recursion detection works correctly
    task_a = Class.new(Taski::Task) do
      def build
        puts "TaskA building"
      end
    end
    Object.const_set(:RecursionTaskA, task_a)

    # Simulate recursion by manually calling ensure_instance_built
    # in a thread context where building flag is already set
    thread = Thread.new do
      Thread.current["RecursionTaskA_building"] = true
      
      # This should raise CircularDependencyError
      assert_raises(Taski::CircularDependencyError) do
        RecursionTaskA.ensure_instance_built
      end
    end

    thread.join
  end

  def test_monitor_synchronization
    # Test that Monitor allows reentrant locking
    task = Class.new(Taski::Task) do
      def build
        puts "Task built successfully"
      end

      def self.test_reentrant_lock
        # This should work with Monitor (but would fail with Mutex)
        build_monitor.synchronize do
          build_monitor.synchronize do
            "nested synchronization works"
          end
        end
      end
    end
    Object.const_set(:MonitorTask, task)

    # This should not raise an error
    assert_equal "nested synchronization works", MonitorTask.test_reentrant_lock
  end
end