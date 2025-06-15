# frozen_string_literal: true

require_relative "test_helper"

class TestLifecycle < Minitest::Test
  include TaskiTestHelper

  def setup
    setup_taski_test
  end

  # === Lifecycle Management Tests ===

  def test_clean_without_build
    # Test that clean works even when build was never called
    task_a = Class.new(Taski::Task) do
      exports :value

      def build
        @value = "built"
        puts "TaskA build"
      end

      def clean
        puts "TaskA clean (value: #{@value || 'not built'})"
      end
    end
    Object.const_set(:CleanTaskA, task_a)

    task_b = Class.new(Taski::Task) do
      def build
        puts "TaskB build with #{CleanTaskA.value}"
      end

      def clean
        puts "TaskB clean"
      end
    end
    Object.const_set(:CleanTaskB, task_b)

    # Call clean without building first
    output = capture_io { CleanTaskB.clean }

    # Verify clean was called but build was not
    assert_includes output[0], "TaskB clean"
    assert_includes output[0], "TaskA clean (value: not built)"
    refute_includes output[0], "TaskA build"
    refute_includes output[0], "TaskB build"
  end

  def test_refresh_functionality
    # Test that refresh works like reset
    task = Class.new(Taski::Task) do
      exports :value

      def build
        @value = "refreshed_#{object_id}"
      end
    end
    Object.const_set(:RefreshTaskA, task)

    # Build the task
    first_value = RefreshTaskA.value
    first_instance = RefreshTaskA.instance_variable_get(:@__task_instance)

    # Refresh the task
    result = RefreshTaskA.refresh

    # Should return self
    assert_equal RefreshTaskA, result

    # Build again - should create new instance
    second_value = RefreshTaskA.value
    second_instance = RefreshTaskA.instance_variable_get(:@__task_instance)

    # Values should be different (different object_id)
    refute_equal first_value, second_value
    refute_equal first_instance, second_instance
  end

  def test_task_reset_functionality
    # Test that reset! clears cached instances
    task = Class.new(Taski::Task) do
      exports :value

      def build
        @value = "built_#{object_id}"
      end
    end
    Object.const_set(:ResetTaskA, task)

    # Build the task
    first_value = ResetTaskA.value
    first_instance = ResetTaskA.instance_variable_get(:@__task_instance)

    # Reset the task
    ResetTaskA.reset!

    # Build again - should create new instance
    second_value = ResetTaskA.value
    second_instance = ResetTaskA.instance_variable_get(:@__task_instance)

    # Values should be different (different object_id)
    refute_equal first_value, second_value
    refute_equal first_instance, second_instance
  end

  def test_circular_dependency_detection
    # Test that circular dependencies are properly detected and raise an error
    task_a = Class.new(Taski::Task) do
      # Manually create circular dependency
      @dependencies = [{ klass: proc { CircularTaskB } }]

      def build
        puts "CircularTaskA"
      end
    end
    Object.const_set(:CircularTaskA, task_a)

    task_b = Class.new(Taski::Task) do
      # Manually create circular dependency back to A
      @dependencies = [{ klass: proc { CircularTaskA } }]

      def build
        puts "CircularTaskB"
      end
    end
    Object.const_set(:CircularTaskB, task_b)

    # Replace the proc references with actual class references
    CircularTaskA.instance_variable_set(:@dependencies, [{ klass: CircularTaskB }])
    CircularTaskB.instance_variable_set(:@dependencies, [{ klass: CircularTaskA }])

    # Attempting to build should raise CircularDependencyError
    assert_raises(Taski::CircularDependencyError) do
      CircularTaskA.build
    end
  end

  def test_method_visibility
    # Test that private methods are properly hidden
    refute Taski::Task.respond_to?(:build_monitor), "build_monitor should be private"
    refute Taski::Task.respond_to?(:build_thread_key), "build_thread_key should be private"
    refute Taski::Task.respond_to?(:extract_class), "extract_class should be private"
    
    # Test that public methods are accessible
    assert Taski::Task.respond_to?(:build), "build should be public"
    assert Taski::Task.respond_to?(:clean), "clean should be public"
    assert Taski::Task.respond_to?(:reset!), "reset! should be public"
    assert Taski::Task.respond_to?(:refresh), "refresh should be public"
  end
end