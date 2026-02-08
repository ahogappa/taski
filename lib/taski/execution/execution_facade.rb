# frozen_string_literal: true

require "monitor"
require_relative "task_output_router"

module Taski
  module Execution
    # Central hub for execution events — provides both Pull (query) and Push
    # (observer notification) interfaces. Holds only construction-time config
    # plus observer/capture plumbing; no mutable domain state.
    #
    # Events (in order): ready, start, task_updated,
    # group_started, group_completed, stop.
    #
    # All observer operations are synchronized using Monitor.
    class ExecutionFacade
      THREAD_LOCAL_KEY = :taski_execution_context

      attr_reader :root_task_class, :dependency_graph

      def initialize(root_task_class:)
        @root_task_class = root_task_class
        @dependency_graph = StaticAnalysis::DependencyGraph.new.build_from_cached(root_task_class).freeze
        @monitor = Monitor.new
        @observers = []
        @output_capture = nil
        @original_stdout = nil
      end

      # Build a facade with the global progress observer attached.
      def self.build_default(root_task_class:)
        facade = new(root_task_class: root_task_class)
        progress = Taski.progress_display
        facade.add_observer(progress) if progress
        facade
      end

      def self.current
        Thread.current[THREAD_LOCAL_KEY]
      end

      def self.current=(context)
        Thread.current[THREAD_LOCAL_KEY] = context
      end

      def output_capture_active?
        @monitor.synchronize { !@output_capture.nil? }
      end

      def original_stdout
        @monitor.synchronize { @original_stdout }
      end

      def original_stderr
        @monitor.synchronize { @original_stderr }
      end

      # Captures $stdout and $stderr using a TaskOutputRouter for inline progress display.
      def setup_output_capture(output_io)
        @monitor.synchronize do
          @original_stdout = output_io
          @original_stderr = $stderr
          @output_capture = TaskOutputRouter.new(@original_stdout, self)
          @output_capture.start_polling
          $stdout = @output_capture
          $stderr = @output_capture
        end
      end

      def teardown_output_capture
        capture = nil
        @monitor.synchronize do
          return unless @original_stdout

          capture = @output_capture
          $stdout = @original_stdout
          $stderr = @original_stderr if @original_stderr
          @output_capture = nil
          @original_stdout = nil
          @original_stderr = nil
        end
        capture&.stop_polling
      end

      def output_capture
        @monitor.synchronize { @output_capture }
      end

      # Delegation to Executor — isolates TaskWrapper from direct Executor dependency.

      def trigger_execution(task_class, registry:)
        Executor.execute(task_class, registry: registry, execution_facade: self)
      end

      def trigger_clean(task_class, registry:)
        Executor.execute_clean(task_class, registry: registry, execution_facade: self)
      end

      def add_observer(observer)
        @monitor.synchronize { @observers << observer }
        observer.context = self if observer.respond_to?(:context=)
      end

      def remove_observer(observer)
        @monitor.synchronize { @observers.delete(observer) }
      end

      def observers
        @monitor.synchronize { @observers.dup }
      end

      # Event notifications — dispatched to all registered observers.

      def notify_ready = dispatch(:on_ready)
      def notify_start = dispatch(:on_start)
      def notify_stop = dispatch(:on_stop)

      def notify_task_updated(task_class, previous_state:, current_state:, phase:, timestamp:)
        dispatch(:on_task_updated, task_class, previous_state: previous_state, current_state: current_state, phase: phase, timestamp: timestamp)
      end

      def notify_group_started(task_class, group_name, phase:, timestamp:)
        dispatch(:on_group_started, task_class, group_name, phase: phase, timestamp: timestamp)
      end

      def notify_group_completed(task_class, group_name, phase:, timestamp:)
        dispatch(:on_group_completed, task_class, group_name, phase: phase, timestamp: timestamp)
      end

      private

      def dispatch(method_name, *args, **kwargs)
        current_observers = @monitor.synchronize { @observers.dup }
        current_observers.each do |observer|
          next unless observer.respond_to?(method_name)

          begin
            if kwargs.empty?
              observer.public_send(method_name, *args)
            else
              observer.public_send(method_name, *args, **kwargs)
            end
          rescue => e
            Taski::Logging.warn(Taski::Logging::Events::OBSERVER_ERROR, observer_class: observer.class.name, method: method_name.to_s, error_message: e.message)
          end
        end
      end
    end
  end
end
