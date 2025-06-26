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
    build_count = 0
    build_mutex = Mutex.new

    task = Class.new(Taski::Task) do
      exports :thread_id, :build_number

      define_method :build do
        build_mutex.synchronize do
          build_count += 1
          @build_number = build_count
        end
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
    assert_equal 1, results.uniq.size, "All threads should receive the same thread_id"
    assert results.all? { |result| result == results.first }

    # Build should have been called exactly once (verify through public API)
    assert_equal 1, ThreadSafeTask.build_number
  end

  def test_concurrent_task_building
    # Test multiple different tasks building concurrently
    # Use a barrier to ensure tasks start at the same time
    barrier = Mutex.new
    start_flag = false

    task_x = Class.new(Taski::Task) do
      exports :x_value, :build_thread_id

      define_method :build do
        # Wait for both threads to be ready
        barrier.synchronize {} until start_flag
        @build_thread_id = Thread.current.object_id
        @x_value = "X-#{@build_thread_id}"
      end
    end
    Object.const_set(:ConcurrentTaskX, task_x)

    task_y = Class.new(Taski::Task) do
      exports :y_value, :build_thread_id

      define_method :build do
        # Wait for both threads to be ready
        barrier.synchronize {} until start_flag
        @build_thread_id = Thread.current.object_id
        @y_value = "Y-#{@build_thread_id}"
      end
    end
    Object.const_set(:ConcurrentTaskY, task_y)

    # Build both tasks concurrently
    threads = [
      Thread.new { ConcurrentTaskX.build },
      Thread.new { ConcurrentTaskY.build }
    ]

    # Start both threads
    start_flag = true

    threads.each(&:join)

    # Both should have built successfully with unique thread IDs
    assert_match(/^X-\d+$/, ConcurrentTaskX.x_value)
    assert_match(/^Y-\d+$/, ConcurrentTaskY.y_value)

    # Verify they were built in different threads
    refute_equal ConcurrentTaskX.build_thread_id, ConcurrentTaskY.build_thread_id
  end

  def test_concurrent_access_to_same_task
    # Test that the same task instance is shared across threads
    task = Class.new(Taski::Task) do
      exports :access_count

      def build
        @access_count = 0
      end

      # Add class method to safely increment count
      def self.increment_count
        instance = build  # This ensures the instance exists
        instance.send(:increment_count_impl)
        instance.access_count
      end

      private

      def increment_count_impl
        @access_count ||= 0
        @access_count += 1
      end
    end
    Object.const_set(:SharedTask, task)

    # Build the task first
    SharedTask.build

    # Multiple threads accessing the same instance through public API
    threads = 10.times.map do
      Thread.new do
        SharedTask.increment_count
      end
    end

    results = threads.map(&:value)

    # Should have incremented exactly 10 times
    # All results should show incrementing count
    assert_equal 10, results.max
    assert_equal 10, SharedTask.access_count
  end

  def test_concurrent_circular_dependency_detection
    # Test that circular dependencies are properly detected in concurrent scenarios

    # Create tasks with actual circular dependency
    task_a = Class.new(Taski::Task) do
      exports :value_a

      def build
        # This creates a circular dependency: A -> B -> A
        @value_a = "A-#{ConcurrentCircularTaskB.value_b}"
      end
    end
    Object.const_set(:ConcurrentCircularTaskA, task_a)

    task_b = Class.new(Taski::Task) do
      exports :value_b

      def build
        @value_b = "B-#{ConcurrentCircularTaskA.value_a}"
      end
    end
    Object.const_set(:ConcurrentCircularTaskB, task_b)

    # Should detect circular dependency and raise error (may be wrapped in TaskBuildError)
    error = assert_raises(Taski::TaskBuildError, Taski::CircularDependencyError) do
      ConcurrentCircularTaskA.build
    end

    # Verify that circular dependency was indeed detected
    assert_includes error.message, "Circular dependency"
  end

  def test_reentrant_task_building
    # Test that tasks can be safely built multiple times from the same thread
    # This implicitly tests that the underlying synchronization mechanism is reentrant

    task = Class.new(Taski::Task) do
      exports :build_count

      def build
        @build_count ||= 0
        @build_count += 1
      end

      def self.test_multiple_builds
        # Multiple builds from same thread should not deadlock
        build  # First build
        build  # Second build should reuse instance, not rebuild
        "multiple builds completed"
      end
    end
    Object.const_set(:ReentrantTask, task)

    # This should not raise an error or deadlock
    assert_equal "multiple builds completed", ReentrantTask.test_multiple_builds

    # Should only have built once due to caching
    assert_equal 1, ReentrantTask.build_count
  end
end
