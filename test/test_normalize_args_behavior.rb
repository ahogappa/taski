# frozen_string_literal: true

require_relative "test_helper"

class TestNormalizeArgsBehavior < Minitest::Test
  include TaskiTestHelper

  def setup
    setup_taski_test
  end

  def test_hash_equality_without_normalization
    # Ruby hashes are equal regardless of key order
    hash1 = {a: 1, b: 2, c: 3}
    hash2 = {c: 3, a: 1, b: 2}
    hash3 = {b: 2, c: 3, a: 1}

    assert_equal hash1, hash2
    assert_equal hash2, hash3
    assert_equal hash1, hash3
  end

  def test_nil_values_should_be_distinguished_from_omitted_values
    # Create a task that distinguishes between nil and omitted values
    task_class = Class.new(Taski::Task) do
      exports :args_received

      def self.name
        "NilDistinguishTask"
      end

      def run
        @args_received = build_args.dup
      end
    end
    Object.const_set(:NilDistinguishTask, task_class)

    # Run with no arguments
    result1 = NilDistinguishTask.run

    # Run with explicit nil
    result2 = NilDistinguishTask.run(value: nil)

    # These should create different instances since arguments are different
    refute_equal result1.object_id, result2.object_id
    assert_equal({}, result1.args_received)
    assert_equal({value: nil}, result2.args_received)
  ensure
    Object.send(:remove_const, :NilDistinguishTask) if Object.const_defined?(:NilDistinguishTask)
  end

  def test_normalize_args_is_unnecessary
    # Direct hash comparison without normalization works correctly
    task_class = Class.new(Taski::Task) do
      exports :call_count, :last_args

      def self.name
        "DirectComparisonTask"
      end

      def initialize(args = {})
        super
        self.class.instance_variable_set(:@call_count, 0) unless self.class.instance_variable_get(:@call_count)
      end

      def run
        self.class.instance_variable_set(:@call_count, self.class.instance_variable_get(:@call_count) + 1)
        @call_count = self.class.instance_variable_get(:@call_count)
        @last_args = build_args.dup
      end
    end
    Object.const_set(:DirectComparisonTask, task_class)

    # Run with same arguments in different order
    result1 = DirectComparisonTask.run(x: 1, y: 2, z: 3)
    result2 = DirectComparisonTask.run(z: 3, x: 1, y: 2)
    result3 = DirectComparisonTask.run(y: 2, z: 3, x: 1)

    # Without normalization, these should still use cache correctly
    # (This test will fail initially, showing that normalize_args might be doing something)
    assert_equal result1.object_id, result2.object_id
    assert_equal result2.object_id, result3.object_id
  ensure
    Object.send(:remove_const, :DirectComparisonTask) if Object.const_defined?(:DirectComparisonTask)
  end

  def test_parametrized_args_comparison
    # Test that argument comparison works correctly without normalization
    task_class = Class.new(Taski::Task) do
      exports :args_received

      def self.name
        "ArgsComparisonTask"
      end

      def run
        @args_received = build_args.dup
      end
    end
    Object.const_set(:ArgsComparisonTask, task_class)

    # Same arguments in different order should still use cache
    result1 = ArgsComparisonTask.run(x: 1, y: 2)
    result2 = ArgsComparisonTask.run(y: 2, x: 1)
    assert_equal result1.object_id, result2.object_id

    # Nil values should be preserved and distinguished
    result3 = ArgsComparisonTask.run(x: 1, y: nil)
    result4 = ArgsComparisonTask.run(x: 1)
    refute_equal result3.object_id, result4.object_id
    assert_equal({x: 1, y: nil}, result3.args_received)
    assert_equal({x: 1}, result4.args_received)
  ensure
    Object.send(:remove_const, :ArgsComparisonTask) if Object.const_defined?(:ArgsComparisonTask)
  end
end
