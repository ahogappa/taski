# frozen_string_literal: true

require_relative "test_helper"

class TestReference < Minitest::Test
  include TaskiTestHelper

  def setup
    setup_taski_test
  end

  # === Reference Class Tests ===

  def test_reference_basic_functionality
    # Test the Reference class functionality
    ref = Taski::Reference.new("String")

    assert_instance_of Taski::Reference, ref
    assert_equal String, ref.deref
    assert ref == String
    assert_equal "&String", ref.inspect
  end

  def test_reference_error_handling
    # Test Reference class error handling
    ref = Taski::Reference.new("NonExistentClass")

    # deref should raise TaskAnalysisError for non-existent class
    error = assert_raises(Taski::TaskAnalysisError) do
      ref.deref
    end

    assert_includes error.message, "Cannot resolve constant 'NonExistentClass'"

    # == should return false for non-existent class
    refute ref == String
  end

  def test_reference_in_dependencies
    # Test that Reference objects work in dependency resolution
    task_a = Class.new(Taski::Task) do
      exports :value

      def build
        TaskiTestHelper.track_build_order("RefDepTaskA")
        @value = "A"
      end
    end
    Object.const_set(:RefDepTaskA, task_a)

    task_b = Class.new(Taski::Task) do
      # Manually add dependency using Reference
      @dependencies = [{klass: Taski::Reference.new("RefDepTaskA")}]

      def build
        TaskiTestHelper.track_build_order("RefDepTaskB")
        puts "B depends on #{RefDepTaskA.value}"
      end
    end
    Object.const_set(:RefDepTaskB, task_b)

    # Reset and build
    TaskiTestHelper.reset_build_order
    capture_io { RefDepTaskB.build }

    # Verify build order
    build_order = TaskiTestHelper.build_order
    task_a_idx = build_order.index("RefDepTaskA")
    task_b_idx = build_order.index("RefDepTaskB")

    assert task_a_idx < task_b_idx, "RefDepTaskA should be built before RefDepTaskB"
  end

  def test_ref_method_usage
    # Test using ref() in different contexts
    task_a = Class.new(Taski::Task) do
      exports :name

      def build
        @name = "TaskA"
        puts "Building TaskA"
      end
    end
    Object.const_set(:RefTaskA, task_a)

    task_b = Class.new(Taski::Task) do
      def build
        # Use ref to get task class from string name
        ref = self.class.ref("RefTaskA")
        task_a_class = ref.is_a?(Taski::Reference) ? ref.deref : ref
        puts "Building TaskB, depends on #{task_a_class.name}"
      end
    end
    Object.const_set(:RefTaskB, task_b)

    output = capture_io { RefTaskB.build }
    assert_includes output[0], "Building TaskB, depends on RefTaskA"
    # Note: ref() at runtime doesn't create automatic dependency
    refute_includes output[0], "Building TaskA"
  end

  # TODO: These tests need to be implemented after fixing ref method
  # def test_ref_tracks_dependencies_during_analysis
  #   # Test that ref() properly tracks dependencies during define block analysis
  # end

  # def test_ref_enables_forward_declaration
  #   # Test the main use case: defining classes in reverse dependency order
  # end

  # def test_ref_error_handling_at_runtime
  #   # Test that ref() handles non-existent classes gracefully at runtime
  # end
end
