# frozen_string_literal: true

require_relative "test_helper"

class TestNamespaceDependencyAnalysis < Minitest::Test
  include TaskiTestHelper

  def setup
    setup_taski_test
  end

  def test_static_analysis_with_relative_namespace_references
    # Test that static analysis can detect relative references within namespaces

    namespace_module = Module.new do
      const_set(:TaskA, Class.new(Taski::Task) do
        exports :value

        def run
          @value = "value_from_A"
        end
      end)

      const_set(:TaskB, Class.new(Taski::Task) do
        def run
          # Relative reference within same namespace - this should be detected
          puts "Using: #{TaskA.value}"
        end
      end)
    end
    Object.const_set(:RelativeTestNamespace, namespace_module)

    # Manually trigger dependency analysis (since method_added might not work in test context)
    RelativeTestNamespace::TaskB.send(:analyze_dependencies_at_definition)

    # Dependencies should be detected for relative references
    dependencies = RelativeTestNamespace::TaskB.instance_variable_get(:@dependencies) || []
    expected_dependency = dependencies.find do |dep|
      dep[:klass] == RelativeTestNamespace::TaskA
    end
    assert expected_dependency, "Static analysis should detect relative reference to TaskA"

    # Tree should show the dependency
    tree_output = RelativeTestNamespace::TaskB.tree(color: false)
    assert_includes tree_output, "RelativeTestNamespace::TaskA", "Tree should include relative dependency"

    expected_tree = "RelativeTestNamespace::TaskB\n└── RelativeTestNamespace::TaskA\n"
    assert_equal expected_tree, tree_output, "Tree should show proper dependency structure for relative references"
  end

  def test_static_analysis_with_conditional_namespaced_tasks
    # Test conditional dependency detection (expected limitation)
    # Static analysis should detect absolute references even in conditional blocks

    consumer_task = Class.new(Taski::Task) do
      def run
        if Object.const_defined?(:ConditionalNamespace)
          puts "Using: #{ConditionalNamespace::ConditionalTask.value}"
        else
          puts "Conditional task not available"
        end
      end
    end
    Object.const_set(:ConditionalConsumerTask, consumer_task)

    # Define the conditional namespace
    conditional_module = Module.new do
      const_set(:ConditionalTask, Class.new(Taski::Task) do
        exports :value

        def run
          @value = "conditional_value"
        end
      end)
    end
    Object.const_set(:ConditionalNamespace, conditional_module)

    # Manually trigger dependency analysis
    ConditionalConsumerTask.send(:analyze_dependencies_at_definition)

    # Dependencies should be detected for absolute references
    dependencies = ConditionalConsumerTask.instance_variable_get(:@dependencies) || []
    conditional_dep = dependencies.find do |dep|
      dep[:klass] == ConditionalNamespace::ConditionalTask
    end
    assert conditional_dep, "Static analysis should detect ConditionalNamespace::ConditionalTask as dependency"

    # Tree should show the dependency
    tree_output = ConditionalConsumerTask.tree(color: false)
    assert_includes tree_output, "ConditionalNamespace::ConditionalTask", "Tree should include conditional dependency"
  end

  def test_tree_display_shows_unresolved_dependencies
    # This test demonstrates the current limitation with unresolved dependencies
    # Future enhancement: could show unresolved dependencies with indication

    consumer_task = Class.new(Taski::Task) do
      def run
        puts "Using: #{UnresolvedNamespace::UnresolvedTask.value}"
      end
    end
    Object.const_set(:UnresolvedConsumerTask, consumer_task)

    # Manually trigger dependency analysis
    UnresolvedConsumerTask.send(:analyze_dependencies_at_definition)

    # Currently unresolved dependencies are not shown (expected behavior)
    tree_output = UnresolvedConsumerTask.tree(color: false)
    assert_equal "UnresolvedConsumerTask\n", tree_output, "Tree shows only root task for unresolved dependencies"

    # Note: Future enhancement could show:
    # "UnresolvedConsumerTask\n└── UnresolvedNamespace::UnresolvedTask (unresolved)\n"
  end

  def test_real_world_example_from_user
    # Test replicates the exact issue reported by the user
    # Based on a.rb and b.rb files in the project

    user_namespace = Module.new do
      const_set(:AA, Class.new(Taski::Task) do
        exports :a_value
        def run
          @a_value = "Value from A"
        end
      end)

      const_set(:AB, Class.new(Taski::Task) do
        def run
          # This exact pattern from user's a.rb - relative reference
          p AA.a_value
        end
      end)
    end
    Object.const_set(:UserTestModule, user_namespace)

    # Manually trigger dependency analysis
    UserTestModule::AB.send(:analyze_dependencies_at_definition)

    # AB should show dependency on AA
    dependencies = UserTestModule::AB.instance_variable_get(:@dependencies) || []
    aa_dependency = dependencies.find do |dep|
      dep[:klass] == UserTestModule::AA
    end
    assert aa_dependency, "User's real example - AB should detect dependency on AA"

    # Tree should show the dependency
    tree_output = UserTestModule::AB.tree(color: false)
    expected_tree = "UserTestModule::AB\n└── UserTestModule::AA\n"
    assert_equal expected_tree, tree_output, "User's real example - tree should show AB -> AA dependency"
  end

  def test_dynamic_constant_resolution_not_detected
    # This is expected behavior - dynamic constant resolution cannot be statically analyzed

    consumer_task = Class.new(Taski::Task) do
      def run
        namespace_name = "DynamicTestNamespace"
        task_name = "DynamicTestTask"
        namespace = Object.const_get(namespace_name)
        task_class = namespace.const_get(task_name)
        puts "Using: #{task_class.value}"
      end
    end
    Object.const_set(:DynamicConsumerTask, consumer_task)

    # Define the dynamic task
    dynamic_module = Module.new do
      const_set(:DynamicTestTask, Class.new(Taski::Task) do
        exports :value

        def run
          @value = "dynamic_value"
        end
      end)
    end
    Object.const_set(:DynamicTestNamespace, dynamic_module)

    # Dependencies should be empty (expected limitation)
    dependencies = DynamicConsumerTask.instance_variable_get(:@dependencies) || []
    assert_empty dependencies, "Dynamic constant resolution should not be detected by static analysis"

    # Tree should not show dynamic dependencies
    tree_output = DynamicConsumerTask.tree(color: false)
    assert_equal "DynamicConsumerTask\n", tree_output, "Tree should not show dynamically resolved dependencies"
  end
end
