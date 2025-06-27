# frozen_string_literal: true

require_relative "test_helper"

class TestTreeDisplay < Minitest::Test
  include TaskiTestHelper

  def setup
    setup_taski_test
  end

  # === Tree Display Tests ===
  # Test dependency tree visualization functionality

  def test_tree_display_simple
    # Test simple dependency tree display
    task_a = Class.new(Taski::Task) do
      exports :value
      def build
        @value = "A"
      end
    end
    Object.const_set(:TreeTaskA, task_a)

    task_b = Class.new(Taski::Task) do
      exports :value
      def build
        @value = "B with #{TreeTaskA.value}"
      end
    end
    Object.const_set(:TreeTaskB, task_b)

    expected = "TreeTaskB\n└── TreeTaskA\n"
    assert_equal expected, TreeTaskB.tree
  end

  def test_tree_display_complex_hierarchy
    # Test complex dependency tree display
    task_a = Class.new(Taski::Task) do
      exports :value
      def build
        @value = "A"
      end
    end
    Object.const_set(:TreeTaskCompA, task_a)

    task_b = Class.new(Taski::Task) do
      exports :value
      def build
        @value = "B with #{TreeTaskCompA.value}"
      end
    end  
    Object.const_set(:TreeTaskCompB, task_b)

    task_c = Class.new(Taski::Task) do
      exports :value
      def build
        @value = "C with #{TreeTaskCompA.value}"
      end
    end
    Object.const_set(:TreeTaskCompC, task_c)

    task_d = Class.new(Taski::Task) do
      exports :value
      def build
        @value = "D with #{TreeTaskCompB.value} and #{TreeTaskCompC.value}"
      end
    end
    Object.const_set(:TreeTaskCompD, task_d)

    result = TreeTaskCompD.tree
    assert_includes result, "TreeTaskCompD"
    assert_includes result, "├── TreeTaskCompB"
    assert_includes result, "└── TreeTaskCompC"
    assert_includes result, "TreeTaskCompA"
  end

  def test_tree_display_deep_nesting
    # Test deep nested dependency tree
    task_d = Class.new(Taski::Task) do
      exports :value
      def build
        @value = "Deep D"
      end
    end
    Object.const_set(:DeepTreeD, task_d)

    task_c = Class.new(Taski::Task) do
      exports :value
      def build
        @value = "Deep C with #{DeepTreeD.value}"
      end
    end
    Object.const_set(:DeepTreeC, task_c)

    task_b = Class.new(Taski::Task) do
      exports :value
      def build
        @value = "Deep B with #{DeepTreeC.value}"
      end
    end
    Object.const_set(:DeepTreeB, task_b)

    task_a = Class.new(Taski::Task) do
      exports :value
      def build
        @value = "Deep A with #{DeepTreeB.value}"
      end
    end
    Object.const_set(:DeepTreeA, task_a)

    result = DeepTreeA.tree
    lines = result.lines

    # Verify proper tree structure
    assert_includes lines[0], "DeepTreeA"
    assert_includes lines[1], "└── DeepTreeB"
    assert_includes lines[2], "    └── DeepTreeC"
    assert_includes lines[3], "        └── DeepTreeD"
  end

  def test_tree_display_circular_detection
    # Test circular dependency detection in tree display
    task_a = Class.new(Taski::Task) do
      exports :value
      
      def self.name
        "CircularTaskA"
      end
      
      def build
        @value = "A"
      end
    end
    
    # Simulate circular dependency by setting dependency to self
    task_a.instance_variable_set(:@dependencies, [{klass: task_a}])
    Object.const_set(:CircularTaskA, task_a)

    result = CircularTaskA.tree
    assert_includes result, "CircularTaskA"
    assert_includes result, "(circular)"
  end

  def test_tree_display_with_multiple_branches
    # Test tree with multiple branches and shared dependencies
    shared_task = Class.new(Taski::Task) do
      exports :shared_value
      def build
        @shared_value = "shared"
      end
    end
    Object.const_set(:SharedTreeTask, shared_task)

    branch_a = Class.new(Taski::Task) do
      exports :value
      def build
        @value = "Branch A with #{SharedTreeTask.shared_value}"
      end
    end
    Object.const_set(:BranchTreeA, branch_a)

    branch_b = Class.new(Taski::Task) do
      exports :value
      def build
        @value = "Branch B with #{SharedTreeTask.shared_value}"
      end
    end
    Object.const_set(:BranchTreeB, branch_b)

    root_task = Class.new(Taski::Task) do
      def build
        puts "Root with #{BranchTreeA.value} and #{BranchTreeB.value}"
      end
    end
    Object.const_set(:RootTreeTask, root_task)

    result = RootTreeTask.tree

    # Verify structure includes all tasks
    assert_includes result, "RootTreeTask"
    assert_includes result, "BranchTreeA"
    assert_includes result, "BranchTreeB"
    assert_includes result, "SharedTreeTask"

    # Verify proper tree formatting
    assert_includes result, "├── BranchTreeA"
    assert_includes result, "└── BranchTreeB"
  end

  def test_tree_display_no_dependencies
    # Test tree display for task with no dependencies
    standalone_task = Class.new(Taski::Task) do
      exports :value
      def build
        @value = "standalone"
      end
    end
    Object.const_set(:StandaloneTreeTask, standalone_task)

    result = StandaloneTreeTask.tree
    assert_equal "StandaloneTreeTask\n", result
  end

  def test_tree_display_with_define_api
    # Test tree display works with define API tasks too
    define_task = Class.new(Taski::Task) do
      exports :config_value

      define :dynamic_config, -> {
        "dynamic config"
      }

      def build
        @config_value = dynamic_config
      end
    end
    Object.const_set(:DefineTreeTask, define_task)

    consumer_task = Class.new(Taski::Task) do
      def build
        puts "Using #{DefineTreeTask.config_value}"
      end
    end
    Object.const_set(:ConsumerTreeTask, consumer_task)

    # Tree should work regardless of which API is used
    result = ConsumerTreeTask.tree
    assert_includes result, "ConsumerTreeTask"
    assert_includes result, "└── DefineTreeTask"
  end
end