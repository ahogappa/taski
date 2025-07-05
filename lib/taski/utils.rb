# frozen_string_literal: true

module Taski
  # Common utility functions for the Taski framework
  module Utils
    # Handle circular dependency error message generation
    module CircularDependencyHelpers
      # Build detailed error message for circular dependencies
      # @param cycle_path [Array<Class>] The circular dependency path
      # @param context [String] Context of the error (dependency, runtime)
      # @return [String] Formatted error message
      def self.build_error_message(cycle_path, context = "dependency")
        path_names = cycle_path.map { |klass| klass.name || klass.to_s }

        message = "Circular dependency detected!\n"
        message += "Cycle: #{path_names.join(" → ")}\n\n"
        message += "The #{context} chain is:\n"

        cycle_path.each_cons(2).with_index do |(from, to), index|
          action = (context == "dependency") ? "depends on" : "is trying to build"
          message += "  #{index + 1}. #{from.name} #{action} → #{to.name}\n"
        end

        message += "\nThis creates an infinite loop that cannot be resolved." if context == "dependency"
        message
      end
    end

    # Common dependency utility functions
    module DependencyUtils
      # Extract class from dependency hash
      # @param dep [Hash] Dependency information
      # @return [Class] The dependency class
      def extract_class(dep)
        klass = dep[:klass]
        klass.is_a?(Reference) ? klass.deref : klass
      end
    end

    # Task execution context for build operations
    class TaskContext
      attr_reader :task_name, :dependencies, :args, :parent_task

      def initialize(task_name, dependencies: [], args: nil, parent_task: nil)
        @task_name = task_name
        @dependencies = dependencies
        @args = args
        @parent_task = parent_task
      end

      def has_args?
        args && !args.empty?
      end

      def formatted_args
        TaskBuildHelpers.format_args(args)
      end

      def args_empty?
        !has_args?
      end
    end

    # Task logging formatter for consistent log output
    class TaskLogger
      LOG_TIMESTAMP_FORMAT = "%Y-%m-%d %H:%M:%S.%3N"
      LOG_INFO_TEMPLATE = "[%s] INFO  Taski: Task build completed (task=%s, duration_ms=%s)"
      LOG_ERROR_TEMPLATE = "[%s] ERROR Taski: Task build failed (task=%s, error=%s, duration_ms=%s)"

      def initialize(context, duration)
        @context = context
        @duration = duration
      end

      def log_success
        Taski.logger.task_build_complete(@context.task_name, duration: @duration)
      rescue IOError
        fallback_log(:info)
      end

      def log_failure(exception)
        Taski.logger.task_build_failed(@context.task_name, error: exception, duration: @duration)
      rescue IOError
        fallback_log(:error, exception)
      end

      private

      def fallback_log(level, exception = nil)
        timestamp = Time.now.strftime(LOG_TIMESTAMP_FORMAT)
        duration_ms = (@duration * 1000).round(2)

        message = case level
        when :info
          LOG_INFO_TEMPLATE % [timestamp, @context.task_name, duration_ms]
        when :error
          LOG_ERROR_TEMPLATE % [timestamp, @context.task_name, exception.message, duration_ms]
        end

        warn message
      end
    end

    # Task build execution session with timing and error handling
    class TaskBuildSession
      # Error message templates
      ERROR_MESSAGE_TEMPLATE = "Failed to build task %s"
      ERROR_WITH_ARGS_TEMPLATE = " with args %s"
      ERROR_WITH_CAUSE_TEMPLATE = ": %s"

      def initialize(context)
        @context = context
        @start_time = nil
        @duration = nil
      end

      # Template Method pattern - defines the algorithm skeleton
      def execute
        start_timing
        begin
          before_execution
          result = perform_execution { yield }
          after_successful_execution(result)
        rescue => e
          after_failed_execution(e)
        end
      end

      protected

      # Template method hooks - can be overridden by subclasses
      def before_execution
        start_logging_and_progress
      end

      def perform_execution
        yield
      end

      def after_successful_execution(result)
        complete_success(result)
      end

      def after_failed_execution(exception)
        handle_failure(exception)
      end

      private

      attr_reader :context

      def start_timing
        @start_time = Time.now
      end

      def calculate_duration
        @duration = Time.now - @start_time
      end

      def start_logging_and_progress
        Taski.logger.task_build_start(context.task_name, dependencies: context.dependencies, args: context.args)
        Taski.progress_display&.start_task(context.task_name, dependencies: context.dependencies)
      end

      def complete_success(result)
        calculate_duration
        complete_progress_success
        log_success
        result
      end

      def complete_progress_success
        Taski.progress_display&.complete_task(context.task_name, duration: @duration)
      end

      def log_success
        task_logger.log_success
      end

      def handle_failure(exception)
        calculate_duration

        # Check for rescue_deps handler first
        if handle_rescue_deps(exception)
          return nil
        end

        complete_progress_failure(exception)
        log_failure(exception)
        raise_build_error(exception)
      end

      def handle_rescue_deps(exception)
        TaskBuildHelpers.send(:handle_rescue_deps, context.parent_task, exception, context.task_name)
      end

      def complete_progress_failure(exception)
        Taski.progress_display&.fail_task(context.task_name, error: exception, duration: @duration)
      end

      def log_failure(exception)
        task_logger.log_failure(exception)
      end

      def task_logger
        @task_logger ||= TaskLogger.new(context, @duration)
      end

      def raise_build_error(exception)
        error_message = build_error_message(exception)
        raise TaskBuildError, error_message
      end

      def build_error_message(exception)
        message = ERROR_MESSAGE_TEMPLATE % context.task_name
        message += ERROR_WITH_ARGS_TEMPLATE % context.formatted_args if context.has_args?
        message += ERROR_WITH_CAUSE_TEMPLATE % exception.message
        message
      end
    end

    # Common task build utility functions
    module TaskBuildHelpers
      # Format arguments hash for display in error messages
      # @param args [Hash] Arguments hash
      # @return [String] Formatted arguments string
      def self.format_args(args)
        return "" if args.nil? || args.empty?

        formatted_pairs = args.map do |key, value|
          "#{key}: #{value.inspect}"
        end
        "{#{formatted_pairs.join(", ")}}"
      end

      # Execute block with comprehensive build logging and progress display
      # @param task_name [String] Name of the task being built
      # @param dependencies [Array] List of dependencies
      # @param args [Hash] Build arguments for parametrized builds
      # @param parent_task [Class] Parent task class for rescue_deps handling
      # @yield Block to execute with logging
      # @return [Object] Result of the block execution
      def self.with_build_logging(task_name, dependencies: [], args: nil, parent_task: nil)
        context = TaskContext.new(task_name, dependencies: dependencies, args: args, parent_task: parent_task)
        session = TaskBuildSession.new(context)
        session.execute { yield }
      end

      class << self
        private

        # Handle rescue_deps error handling using Chain of Responsibility
        # @param parent_task [Class] Parent task class
        # @param exception [Exception] Exception to handle
        # @param task_name [String] Failed task name
        # @return [Boolean] true if handled and should continue, false if should fall through
        def handle_rescue_deps(parent_task, exception, task_name)
          RescueDepsChain.new(parent_task, exception, task_name).handle
        end

        # Handle the result from rescue handler using Strategy pattern
        # @param result [Object] Result from rescue handler
        # @return [Boolean] true if should continue, false if should fall through
        def handle_rescue_result(result)
          RescueResultStrategies.handle(result)
        end
      end
    end

    # Chain of Responsibility pattern for rescue_deps processing
    class RescueDepsChain
      def initialize(parent_task, exception, task_name)
        @parent_task = parent_task
        @exception = exception
        @task_name = task_name
      end

      def handle
        return false unless parent_task_supports_rescue?
        return false unless handler_exists?

        result = execute_handler_with_fallback
        return false unless result

        RescueResultStrategies.handle(result)
      end

      private

      attr_reader :parent_task, :exception, :task_name

      def parent_task_supports_rescue?
        @parent_task&.respond_to?(:find_dependency_rescue_handler)
      end

      def handler_exists?
        handler_pair = @parent_task.find_dependency_rescue_handler(@exception)
        @handler_pair = handler_pair
        !handler_pair.nil?
      end

      def execute_handler_with_fallback
        _exception_class, handler = @handler_pair
        failed_task_class = resolve_task_class(@task_name)

        execute_rescue_handler(handler, @exception, failed_task_class)
      end

      def resolve_task_class(task_name)
        Object.const_get(task_name)
      rescue NameError
        nil
      end

      def execute_rescue_handler(handler, exception, failed_task_class)
        handler.call(exception, failed_task_class)
      rescue => handler_error
        warn "rescue_deps handler failed: #{handler_error.message}"
        nil
      end
    end

    # Strategy pattern for handling rescue_deps results
    module RescueResultStrategies
      class ContinueStrategy
        def self.handle(result)
          return false unless result.nil?
          true  # Continue processing
        end
      end

      class ReraiseStrategy
        def self.handle(result)
          return false unless result == :reraise
          false  # Fall through to normal error handling
        end
      end

      class CustomExceptionStrategy
        def self.handle(result)
          return false if result.nil? || result == :reraise

          if result.is_a?(Exception)
            raise result
          end
          false  # For any other return value, fall through to normal error handling
        end
      end

      STRATEGIES = [
        ContinueStrategy,
        ReraiseStrategy,
        CustomExceptionStrategy
      ].freeze

      def self.handle(result)
        STRATEGIES.each do |strategy|
          handled_result = strategy.handle(result)
          return handled_result if handled_result != false || strategy == CustomExceptionStrategy
        end
        false
      end
    end
  end
end
