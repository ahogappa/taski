# frozen_string_literal: true

require_relative "test_helper"
require "taski/execution/progress_event_subscriber"

module Taski
  module Execution
    class TestProgressEventSubscriber < Minitest::Test
      def setup
        @events = []
      end

      # ========================================
      # Callback Registration Tests
      # ========================================

      def test_on_execution_start_callback
        subscriber = ProgressEventSubscriber.new do |events|
          events.on_execution_start { @events << :start }
        end

        subscriber.start
        assert_equal [:start], @events
      end

      def test_on_execution_stop_callback
        subscriber = ProgressEventSubscriber.new do |events|
          events.on_execution_stop { @events << :stop }
        end

        subscriber.stop
        assert_equal [:stop], @events
      end

      def test_on_task_start_callback
        task_class = Class.new
        Object.const_set(:SubscriberTask1, task_class) unless defined?(SubscriberTask1)

        subscriber = ProgressEventSubscriber.new do |events|
          events.on_task_start { |tc, info| @events << [:task_start, tc, info] }
        end

        subscriber.update_task(SubscriberTask1, state: :running)

        assert_equal 1, @events.size
        assert_equal :task_start, @events.first[0]
        assert_equal SubscriberTask1, @events.first[1]
      end

      def test_on_task_complete_callback
        task_class = Class.new
        Object.const_set(:SubscriberTask2, task_class) unless defined?(SubscriberTask2)

        subscriber = ProgressEventSubscriber.new do |events|
          events.on_task_complete { |tc, info| @events << [:task_complete, tc, info] }
        end

        subscriber.update_task(SubscriberTask2, state: :completed, duration: 123.5)

        assert_equal 1, @events.size
        assert_equal :task_complete, @events.first[0]
        assert_equal SubscriberTask2, @events.first[1]
        assert_equal 123.5, @events.first[2][:duration]
      end

      def test_on_task_fail_callback
        task_class = Class.new
        Object.const_set(:SubscriberTask3, task_class) unless defined?(SubscriberTask3)
        error = StandardError.new("test error")

        subscriber = ProgressEventSubscriber.new do |events|
          events.on_task_fail { |tc, info| @events << [:task_fail, tc, info] }
        end

        subscriber.update_task(SubscriberTask3, state: :failed, error: error)

        assert_equal 1, @events.size
        assert_equal :task_fail, @events.first[0]
        assert_equal SubscriberTask3, @events.first[1]
        assert_equal error, @events.first[2][:error]
      end

      def test_on_task_skip_callback
        task_class = Class.new
        Object.const_set(:SubscriberTask4, task_class) unless defined?(SubscriberTask4)

        subscriber = ProgressEventSubscriber.new do |events|
          events.on_task_skip { |tc, info| @events << [:task_skip, tc, info] }
        end

        subscriber.update_task(SubscriberTask4, state: :skipped)

        assert_equal 1, @events.size
        assert_equal :task_skip, @events.first[0]
        assert_equal SubscriberTask4, @events.first[1]
      end

      def test_on_group_start_callback
        task_class = Class.new
        Object.const_set(:SubscriberTask5, task_class) unless defined?(SubscriberTask5)

        subscriber = ProgressEventSubscriber.new do |events|
          events.on_group_start { |tc, name| @events << [:group_start, tc, name] }
        end

        subscriber.update_group(SubscriberTask5, "Building", state: :running)

        assert_equal 1, @events.size
        assert_equal :group_start, @events.first[0]
        assert_equal SubscriberTask5, @events.first[1]
        assert_equal "Building", @events.first[2]
      end

      def test_on_group_complete_callback
        task_class = Class.new
        Object.const_set(:SubscriberTask6, task_class) unless defined?(SubscriberTask6)

        subscriber = ProgressEventSubscriber.new do |events|
          events.on_group_complete { |tc, name, info| @events << [:group_complete, tc, name, info] }
        end

        subscriber.update_group(SubscriberTask6, "Building", state: :completed, duration: 50.0)

        assert_equal 1, @events.size
        assert_equal :group_complete, @events.first[0]
        assert_equal SubscriberTask6, @events.first[1]
        assert_equal "Building", @events.first[2]
        assert_equal 50.0, @events.first[3][:duration]
      end

      def test_on_progress_callback
        task1 = Class.new
        task2 = Class.new
        Object.const_set(:ProgressTask1, task1) unless defined?(ProgressTask1)
        Object.const_set(:ProgressTask2, task2) unless defined?(ProgressTask2)

        subscriber = ProgressEventSubscriber.new do |events|
          events.on_progress { |summary| @events << [:progress, summary] }
        end

        subscriber.register_task(ProgressTask1)
        subscriber.register_task(ProgressTask2)
        subscriber.update_task(ProgressTask1, state: :completed, duration: 100)

        # Should have been called at least once
        assert @events.any? { |e| e[0] == :progress }
        last_progress = @events.reverse.find { |e| e[0] == :progress }
        assert_equal 1, last_progress[1][:completed]
        assert_equal 2, last_progress[1][:total]
      end

      # ========================================
      # Multiple Callbacks Tests
      # ========================================

      def test_multiple_callbacks_for_same_event
        task_class = Class.new
        Object.const_set(:MultiTask1, task_class) unless defined?(MultiTask1)

        subscriber = ProgressEventSubscriber.new do |events|
          events.on_task_start { |tc, _| @events << [:callback1, tc] }
          events.on_task_start { |tc, _| @events << [:callback2, tc] }
        end

        subscriber.update_task(MultiTask1, state: :running)

        assert_equal 2, @events.size
        assert_equal [:callback1, MultiTask1], @events[0]
        assert_equal [:callback2, MultiTask1], @events[1]
      end

      def test_mixed_callbacks
        task_class = Class.new
        Object.const_set(:MixedTask1, task_class) unless defined?(MixedTask1)

        subscriber = ProgressEventSubscriber.new do |events|
          events.on_task_start { |tc, _| @events << [:start, tc] }
          events.on_task_complete { |tc, _| @events << [:complete, tc] }
        end

        subscriber.update_task(MixedTask1, state: :running)
        subscriber.update_task(MixedTask1, state: :completed, duration: 100)

        assert_equal [[:start, MixedTask1], [:complete, MixedTask1]], @events
      end

      # ========================================
      # No Callback Registered Tests
      # ========================================

      def test_no_callback_registered_does_not_error
        task_class = Class.new
        Object.const_set(:NoCallbackTask, task_class) unless defined?(NoCallbackTask)

        subscriber = ProgressEventSubscriber.new

        # These should not raise any errors
        subscriber.start
        subscriber.register_task(NoCallbackTask)
        subscriber.update_task(NoCallbackTask, state: :running)
        subscriber.update_task(NoCallbackTask, state: :completed, duration: 100)
        subscriber.update_group(NoCallbackTask, "Build", state: :running)
        subscriber.update_group(NoCallbackTask, "Build", state: :completed, duration: 50)
        subscriber.stop
      end

      def test_partial_callbacks_registered
        task_class = Class.new
        Object.const_set(:PartialTask, task_class) unless defined?(PartialTask)

        subscriber = ProgressEventSubscriber.new do |events|
          events.on_task_complete { |tc, _| @events << [:complete, tc] }
        end

        # start callback not registered - should not error
        subscriber.update_task(PartialTask, state: :running)
        subscriber.update_task(PartialTask, state: :completed, duration: 100)

        # Only complete callback should have been called
        assert_equal [[:complete, PartialTask]], @events
      end

      # ========================================
      # Observer Protocol Compatibility Tests
      # ========================================

      def test_implements_observer_protocol
        subscriber = ProgressEventSubscriber.new

        assert_respond_to subscriber, :start
        assert_respond_to subscriber, :stop
        assert_respond_to subscriber, :register_task
        assert_respond_to subscriber, :update_task
        assert_respond_to subscriber, :update_group
      end

      def test_set_root_task
        task_class = Class.new
        Object.const_set(:RootTask, task_class) unless defined?(RootTask)

        subscriber = ProgressEventSubscriber.new do |events|
          events.on_execution_start { @events << [:root_set, subscriber.root_task_class] }
        end

        subscriber.set_root_task(RootTask)
        subscriber.start

        assert_equal RootTask, subscriber.root_task_class
        assert_equal [[:root_set, RootTask]], @events
      end

      def test_set_output_capture
        subscriber = ProgressEventSubscriber.new

        mock_capture = Object.new
        subscriber.set_output_capture(mock_capture)

        # Should not error and capture should be stored
        assert_equal mock_capture, subscriber.output_capture
      end

      # ========================================
      # Clean Lifecycle Tests
      # ========================================

      def test_on_task_cleaning_callback
        task_class = Class.new
        Object.const_set(:CleanTask1, task_class) unless defined?(CleanTask1)

        subscriber = ProgressEventSubscriber.new do |events|
          events.on_task_cleaning { |tc, info| @events << [:cleaning, tc, info] }
        end

        subscriber.update_task(CleanTask1, state: :cleaning)

        assert_equal 1, @events.size
        assert_equal :cleaning, @events.first[0]
        assert_equal CleanTask1, @events.first[1]
      end

      def test_on_task_clean_complete_callback
        task_class = Class.new
        Object.const_set(:CleanTask2, task_class) unless defined?(CleanTask2)

        subscriber = ProgressEventSubscriber.new do |events|
          events.on_task_clean_complete { |tc, info| @events << [:clean_complete, tc, info] }
        end

        subscriber.update_task(CleanTask2, state: :clean_completed, duration: 50.0)

        assert_equal 1, @events.size
        assert_equal :clean_complete, @events.first[0]
        assert_equal CleanTask2, @events.first[1]
        assert_equal 50.0, @events.first[2][:duration]
      end

      def test_on_task_clean_fail_callback
        task_class = Class.new
        Object.const_set(:CleanTask3, task_class) unless defined?(CleanTask3)
        error = StandardError.new("clean error")

        subscriber = ProgressEventSubscriber.new do |events|
          events.on_task_clean_fail { |tc, info| @events << [:clean_fail, tc, info] }
        end

        subscriber.update_task(CleanTask3, state: :clean_failed, error: error)

        assert_equal 1, @events.size
        assert_equal :clean_fail, @events.first[0]
        assert_equal CleanTask3, @events.first[1]
        assert_equal error, @events.first[2][:error]
      end
    end
  end
end
