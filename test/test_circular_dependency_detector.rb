# frozen_string_literal: true

require_relative "test_helper"

class TestCircularDependencyDetector < Minitest::Test
  include TaskiTestHelper

  def setup
    setup_taski_test
  end

  # RED: 最初の失敗テスト
  def test_circular_dependency_detector_can_be_created
    detector = Taski::CircularDependencyDetector.new(TestTask)
    assert detector, "CircularDependencyDetector should be created successfully"
  end

  # RED: 基本機能テスト
  def test_can_check_for_circular_dependency
    detector = Taski::CircularDependencyDetector.new(TestTask)
    detector.check_circular_dependency
    # とりあえず例外が出なければOK（仮実装段階）
  end

  # RED: 三角測量のためのテスト - 実際の循環依存検出
  def test_detects_actual_circular_dependency
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

    detector = Taski::CircularDependencyDetector.new(CircularTaskA)

    assert_raises(Taski::CircularDependencyError) do
      detector.check_circular_dependency
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
