# frozen_string_literal: true

require "test_helper"
require "taski/static_analysis/tree_builder"

class TestTreeBuilder < Minitest::Test
  def test_builds_tree_for_single_task
    task_class = stub_task_class("RootTask")

    tree = Taski::StaticAnalysis::TreeBuilder.build_tree(task_class)

    assert_equal task_class, tree[:task_class]
    assert_equal [], tree[:children]
    assert_equal false, tree[:is_section]
    assert_equal false, tree[:is_circular]
    assert_equal false, tree[:is_impl_candidate]
  end

  def test_builds_tree_with_dependencies
    child = stub_task_class("ChildTask")
    parent = stub_task_class_with_deps("ParentTask", [child])

    tree = Taski::StaticAnalysis::TreeBuilder.build_tree(parent)

    assert_equal parent, tree[:task_class]
    assert_equal 1, tree[:children].size

    child_node = tree[:children].first
    assert_equal child, child_node[:task_class]
    assert_equal [], child_node[:children]
  end

  def test_detects_circular_reference
    # Create a circular dependency using a mock
    task_a = stub_task_class("TaskA")
    task_b = stub_task_class("TaskB")

    # TaskA depends on TaskB, TaskB depends on TaskA (circular)
    task_a.define_singleton_method(:cached_dependencies) { [task_b] }
    task_b.define_singleton_method(:cached_dependencies) { [task_a] }

    tree = Taski::StaticAnalysis::TreeBuilder.build_tree(task_a)

    # First level: TaskA -> TaskB
    assert_equal task_a, tree[:task_class]
    assert_equal false, tree[:is_circular]
    assert_equal 1, tree[:children].size

    # Second level: TaskB -> TaskA (circular detected)
    task_b_node = tree[:children].first
    assert_equal task_b, task_b_node[:task_class]
    assert_equal false, task_b_node[:is_circular]
    assert_equal 1, task_b_node[:children].size

    # Third level: TaskA is circular (already visited)
    task_a_circular = task_b_node[:children].first
    assert_equal task_a, task_a_circular[:task_class]
    assert_equal true, task_a_circular[:is_circular]
    assert_equal [], task_a_circular[:children] # No children for circular node
  end

  def test_detects_section_class
    section_class = stub_section_class("MySection")

    tree = Taski::StaticAnalysis::TreeBuilder.build_tree(section_class)

    assert_equal true, tree[:is_section]
  end

  def test_detects_impl_candidate_for_section
    # Create a section with nested impl candidates
    impl_candidate = stub_task_class("MySection::ImplA")
    section_class = stub_section_class_with_deps("MySection", [impl_candidate])

    tree = Taski::StaticAnalysis::TreeBuilder.build_tree(section_class)

    assert_equal true, tree[:is_section]
    assert_equal 1, tree[:children].size

    impl_node = tree[:children].first
    assert_equal impl_candidate, impl_node[:task_class]
    assert_equal true, impl_node[:is_impl_candidate]
  end

  def test_non_nested_dependency_is_not_impl_candidate
    # Create a section with a non-nested dependency
    regular_dep = stub_task_class("RegularDep")
    section_class = stub_section_class_with_deps("MySection", [regular_dep])

    tree = Taski::StaticAnalysis::TreeBuilder.build_tree(section_class)

    impl_node = tree[:children].first
    assert_equal false, impl_node[:is_impl_candidate]
  end

  def test_uses_dependency_graph_when_provided
    child = stub_task_class("ChildTask")
    parent = stub_task_class("ParentTask")

    # Create a mock dependency graph
    mock_graph = Object.new
    mock_graph.define_singleton_method(:dependencies_for) do |task_class|
      if task_class.name == "ParentTask"
        Set.new([child])
      else
        Set.new
      end
    end

    tree = Taski::StaticAnalysis::TreeBuilder.build_tree(parent, dependency_graph: mock_graph)

    assert_equal parent, tree[:task_class]
    assert_equal 1, tree[:children].size
    assert_equal child, tree[:children].first[:task_class]
  end

  def test_builds_deep_nested_tree
    grandchild = stub_task_class("GrandChild")
    child = stub_task_class_with_deps("Child", [grandchild])
    parent = stub_task_class_with_deps("Parent", [child])

    tree = Taski::StaticAnalysis::TreeBuilder.build_tree(parent)

    assert_equal parent, tree[:task_class]
    assert_equal 1, tree[:children].size

    child_node = tree[:children].first
    assert_equal child, child_node[:task_class]
    assert_equal 1, child_node[:children].size

    grandchild_node = child_node[:children].first
    assert_equal grandchild, grandchild_node[:task_class]
    assert_equal [], grandchild_node[:children]
  end

  private

  def stub_task_class(name)
    klass = Class.new
    klass.define_singleton_method(:name) { name }
    klass.define_singleton_method(:cached_dependencies) { [] }
    klass
  end

  def stub_task_class_with_deps(name, deps)
    klass = Class.new
    klass.define_singleton_method(:name) { name }
    klass.define_singleton_method(:cached_dependencies) { deps }
    klass
  end

  def stub_section_class(name)
    # Create a class that inherits from Taski::Section (if defined)
    klass = if defined?(Taski::Section)
              Class.new(Taski::Section)
            else
              Class.new
            end
    klass.define_singleton_method(:name) { name }
    klass.define_singleton_method(:cached_dependencies) { [] }

    # Mark it as a section for testing
    klass.define_singleton_method(:section?) { true }
    klass
  end

  def stub_section_class_with_deps(name, deps)
    klass = if defined?(Taski::Section)
              Class.new(Taski::Section)
            else
              Class.new
            end
    klass.define_singleton_method(:name) { name }
    klass.define_singleton_method(:cached_dependencies) { deps }
    klass.define_singleton_method(:section?) { true }
    klass
  end
end
