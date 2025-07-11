# frozen_string_literal: true

require_relative "test_helper"

class TestTaskComponent < Minitest::Test
  include TaskiTestHelper

  def setup
    setup_taski_test
  end

  def test_task_component_can_be_included
    manager = TestTaskComponentImplementation.new(TestTask)
    assert manager, "TaskComponent implementation should be created successfully"
  end

  def test_can_manage_thread_state
    manager = TestTaskComponentImplementation.new(TestTask)
    result = nil
    manager.with_build_tracking do
      result = "executed"
    end
    assert_equal "executed", result
  end

  def test_manages_thread_local_state_properly
    manager = TestTaskComponentImplementation.new(TestTask)
    thread_key = "#{TestTask.name}_building"

    assert !Thread.current[thread_key], "Thread key should be false initially"

    manager.with_build_tracking do
      assert Thread.current[thread_key], "Thread key should be true during tracking"
    end

    assert !Thread.current[thread_key], "Thread key should be false after tracking"
  end

  private

  class TestTaskComponentImplementation
    include Taski::TaskComponent
  end

  class TestTask < Taski::Task
    def run
    end
  end
end
