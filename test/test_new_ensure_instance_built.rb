# frozen_string_literal: true

require_relative "test_helper"

class TestNewEnsureInstanceBuilt < Minitest::Test
  include TaskiTestHelper

  def setup
    setup_taski_test
  end

  # RED: 新しいensure_instance_builtメソッドのテスト
  def test_ensure_instance_built_returns_singleton_instance
    # テスト開始前にリセット
    TestTask.reset!

    # 最初の呼び出しでインスタンスを作成
    instance1 = TestTask.ensure_instance_built
    assert instance1, "ensure_instance_built should return an instance"
    assert_instance_of TestTask, instance1

    # 2回目の呼び出しでは同じインスタンスを返す（シングルトン）
    instance2 = TestTask.ensure_instance_built
    assert_same instance1, instance2, "ensure_instance_built should return the same instance"
  end

  # RED: 依存関係を持つタスクのテスト
  def test_ensure_instance_built_with_dependencies
    # 依存関係を持つタスククラスを作成
    dep_task = Class.new(Taski::Task) do
      def run
        @executed = true
      end

      def executed?
        @executed
      end
    end
    Object.const_set(:DepTask, dep_task)

    main_task = Class.new(Taski::Task) do
      def run
        DepTask.ensure_instance_built
        @main_executed = true
      end

      def main_executed?
        @main_executed
      end
    end
    Object.const_set(:MainTaskWithDep, main_task)

    # メインタスクを実行
    main_instance = MainTaskWithDep.ensure_instance_built
    assert main_instance.main_executed?, "Main task should be executed"

    # 依存関係も実行されていることを確認
    dep_instance = DepTask.current_instance
    assert dep_instance.executed?, "Dependency task should be executed"
  end

  # RED: 循環依存検出のテスト
  def test_ensure_instance_built_detects_circular_dependency
    # 循環依存のあるタスククラスを作成
    task_a = Class.new(Taski::Task) do
      def run
        CircularDepTaskB.ensure_instance_built
      end
    end
    Object.const_set(:CircularDepTaskA, task_a)

    task_b = Class.new(Taski::Task) do
      def run
        CircularDepTaskA.ensure_instance_built  # 循環依存
      end
    end
    Object.const_set(:CircularDepTaskB, task_b)

    error = assert_raises(Taski::TaskBuildError) do
      CircularDepTaskA.ensure_instance_built
    end
    assert_match(/Circular dependency detected/, error.message)
  end

  # RED: リセット機能のテスト
  def test_ensure_instance_built_after_reset
    # 最初のインスタンスを作成
    instance1 = TestTask.ensure_instance_built
    assert instance1, "ensure_instance_built should return an instance"

    # リセット
    TestTask.reset!

    # 新しいインスタンスが作成される
    instance2 = TestTask.ensure_instance_built
    assert instance2, "ensure_instance_built should return an instance after reset"
    refute_same instance1, instance2, "ensure_instance_built should return a new instance after reset"
  end

  private

  # テスト用の簡単なタスククラス
  class TestTask < Taski::Task
    def run
      @executed = true
    end

    def executed?
      @executed
    end
  end
end
