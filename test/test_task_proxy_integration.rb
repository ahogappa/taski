# frozen_string_literal: true

require "test_helper"
require_relative "fixtures/task_proxy_tasks"

class TestTaskProxyIntegration < Minitest::Test
  def setup
    Taski::Task.reset! if defined?(Taski::Task)
  end

  def test_proxy_transparent_in_interpolation
    task_class = TaskProxyFixtures::InterpolationTask
    execute(task_class)
    wrapper = get_wrapper(task_class)
    assert wrapper.completed?
    assert_equal "result: hello", wrapper.task.value
  end

  def test_proxy_transparent_in_method_chain
    task_class = TaskProxyFixtures::MethodChainTask
    execute(task_class)
    wrapper = get_wrapper(task_class)
    assert wrapper.completed?
    assert_equal "HELLO", wrapper.task.value
  end

  def test_proxy_auto_resolves_direct_ivar_assignment
    task_class = TaskProxyFixtures::DirectAssignTask
    execute(task_class)
    wrapper = get_wrapper(task_class)
    assert wrapper.completed?
    assert_equal "hello", wrapper.task.value
    # The exported value should be the actual string, not a proxy
    refute wrapper.task.value.is_a?(Taski::TaskProxy) if defined?(Taski::TaskProxy)
  end

  def test_multiple_proxies_resolve_correctly
    task_class = TaskProxyFixtures::MultiDepTask
    execute(task_class)
    wrapper = get_wrapper(task_class)
    assert wrapper.completed?
    assert_equal "hello:42", wrapper.task.value
  end

  def test_await_resolves_eagerly
    task_class = TaskProxyFixtures::AwaitTask
    execute(task_class)
    wrapper = get_wrapper(task_class)
    assert wrapper.completed?
    assert_equal "awaited: hello", wrapper.task.value
  end

  def test_await_with_multiple_deps
    task_class = TaskProxyFixtures::MultiAwaitTask
    execute(task_class)
    wrapper = get_wrapper(task_class)
    assert wrapper.completed?
    assert_equal "hello:42", wrapper.task.value
  end

  private

  def execute(task_class)
    registry = Taski::Execution::Registry.new
    @execution_facade = Taski::Execution::ExecutionFacade.new(root_task_class: task_class)
    @registry = registry

    executor = Taski::Execution::Executor.new(
      registry: registry,
      execution_facade: @execution_facade
    )

    executor.execute(task_class)
  end

  def get_wrapper(task_class)
    @registry.create_wrapper(task_class, execution_facade: @execution_facade)
  end
end
