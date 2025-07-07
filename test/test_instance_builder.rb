# frozen_string_literal: true

require_relative "test_helper"

class TestInstanceBuilder < Minitest::Test
  include TaskiTestHelper

  def setup
    setup_taski_test
  end

  # RED: 最初の失敗テスト
  def test_instance_builder_can_be_created
    builder = Taski::InstanceBuilder.new(TestTask)
    assert builder, "InstanceBuilder should be created successfully"
  end

  # RED: 基本機能テスト
  def test_can_build_instance
    builder = Taski::InstanceBuilder.new(TestTask)
    instance = builder.build_instance
    assert instance, "build_instance should return an instance"
    assert_instance_of TestTask, instance
  end

  # RED: 三角測量のためのテスト - 依存関係を持つタスクのインスタンス構築
  def test_builds_instance_with_dependencies
    # 依存関係を持つタスククラスを作成
    dep_task = Class.new(Taski::Task) do
      def run
        # 依存関係のタスクとして動作
      end
    end
    Object.const_set(:DepTask, dep_task)

    main_task = Class.new(Taski::Task) do
      def run
        DepTask.ensure_instance_built
        # メインタスクとして動作
      end
    end
    Object.const_set(:MainWithDepTask, main_task)

    builder = Taski::InstanceBuilder.new(MainWithDepTask)
    instance = builder.build_instance

    assert instance, "build_instance should return an instance"
    assert_instance_of MainWithDepTask, instance
  end

  # RED: 循環依存検出のテスト
  def test_detects_circular_dependency
    # 循環依存のあるタスククラスを作成
    task_a = Class.new(Taski::Task) do
      def run
        CircularTaskB.ensure_instance_built
      end
    end
    Object.const_set(:CircularTaskA, task_a)

    task_b = Class.new(Taski::Task) do
      def run
        CircularTaskA.ensure_instance_built  # 循環依存
      end
    end
    Object.const_set(:CircularTaskB, task_b)

    # Thread.currentに循環依存の状態を模擬設定
    thread_key = "CircularTaskA_building"
    Thread.current[thread_key] = true

    builder = Taski::InstanceBuilder.new(CircularTaskA)

    assert_raises(Taski::CircularDependencyError) do
      builder.build_instance
    end
  ensure
    # クリーンアップ
    Thread.current[thread_key] = false
  end

  private

  # テスト用の簡単なタスククラス
  class TestTask < Taski::Task
    def run
      # 何もしない
    end
  end
end
