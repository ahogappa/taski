# frozen_string_literal: true

require "test_helper"

class TestScheduler < Minitest::Test
  def setup
    Taski::Task.reset! if defined?(Taski::Task)
  end

  def test_build_dependency_graph_single_task
    task = Class.new(Taski::Task) do
      exports :value
      def run
        @value = "test"
      end
    end

    scheduler = Taski::Execution::Scheduler.new
    scheduler.build_dependency_graph(task)

    refute scheduler.completed?(task)
  end

  def test_next_ready_tasks_returns_pending_tasks
    task = Class.new(Taski::Task) do
      exports :value
      def run
        @value = "test"
      end
    end

    scheduler = Taski::Execution::Scheduler.new
    scheduler.build_dependency_graph(task)

    ready = scheduler.next_ready_tasks

    assert_includes ready, task
  end

  def test_mark_enqueued_prevents_re_enqueueing
    task = Class.new(Taski::Task) do
      exports :value
      def run
        @value = "test"
      end
    end

    scheduler = Taski::Execution::Scheduler.new
    scheduler.build_dependency_graph(task)

    ready1 = scheduler.next_ready_tasks
    assert_includes ready1, task

    scheduler.mark_enqueued(task)

    ready2 = scheduler.next_ready_tasks
    refute_includes ready2, task
  end

  def test_mark_completed
    task = Class.new(Taski::Task) do
      exports :value
      def run
        @value = "test"
      end
    end

    scheduler = Taski::Execution::Scheduler.new
    scheduler.build_dependency_graph(task)

    scheduler.mark_enqueued(task)
    scheduler.mark_completed(task)

    assert scheduler.completed?(task)
  end

  def test_running_tasks_returns_true_when_tasks_enqueued
    task = Class.new(Taski::Task) do
      exports :value
      def run
        @value = "test"
      end
    end

    scheduler = Taski::Execution::Scheduler.new
    scheduler.build_dependency_graph(task)

    refute scheduler.running_tasks?

    scheduler.mark_enqueued(task)
    assert scheduler.running_tasks?

    scheduler.mark_completed(task)
    refute scheduler.running_tasks?
  end
end
