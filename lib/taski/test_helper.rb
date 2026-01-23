# frozen_string_literal: true

require_relative "test_helper/errors"
require_relative "test_helper/mock_wrapper"
require_relative "test_helper/mock_registry"

module Taski
  # Test helper module for mocking Taski task dependencies in unit tests.
  # Include this module in your test class to access mocking functionality.
  #
  # @example Minitest usage
  #   class BuildReportTest < Minitest::Test
  #     include Taski::TestHelper
  #
  #     def test_builds_report
  #       mock_task(FetchData, users: [1, 2, 3])
  #       assert_equal 3, BuildReport.user_count
  #     end
  #   end
  module TestHelper
    # Module prepended to Task's singleton class to intercept define_class_accessor.
    # @api private
    module TaskExtension
      def define_class_accessor(method)
        singleton_class.undef_method(method) if singleton_class.method_defined?(method)

        define_singleton_method(method) do
          # Check for mock first
          mock = MockRegistry.mock_for(self)
          return mock.get_exported_value(method) if mock

          # No mock - call original implementation via registry lookup
          registry = Taski.current_registry
          if registry
            wrapper = registry.get_or_create(self) do
              task_instance = allocate
              task_instance.__send__(:initialize)
              Execution::TaskWrapper.new(
                task_instance,
                registry: registry,
                execution_context: Execution::ExecutionContext.current
              )
            end
            wrapper.get_exported_value(method)
          else
            Taski.send(:with_env, root_task: self) do
              Taski.send(:with_args, options: {}) do
                validate_no_circular_dependencies!
                fresh_wrapper.get_exported_value(method)
              end
            end
          end
        end
      end
    end

    # Module prepended to Scheduler to skip dependencies of mocked tasks.
    # @api private
    module SchedulerExtension
      def build_dependency_graph(root_task_class)
        queue = [root_task_class]

        while (task_class = queue.shift)
          next if @task_states.key?(task_class)

          # Mocked tasks have no dependencies (isolates indirect dependencies)
          mock = MockRegistry.mock_for(task_class)
          deps = mock ? Set.new : task_class.cached_dependencies
          @dependencies[task_class] = deps.dup
          @task_states[task_class] = Taski::Execution::Scheduler::STATE_PENDING

          deps.each { |dep| queue << dep }
        end
      end
    end

    # Module prepended to Executor to skip execution of mocked tasks.
    # @api private
    module ExecutorExtension
      def execute_task(task_class, wrapper)
        return if @registry.abort_requested?

        # Skip execution if task is mocked
        if MockRegistry.mock_for(task_class)
          wrapper.mark_completed(nil)
          @completion_queue.push({task_class: task_class, wrapper: wrapper})
          return
        end

        super
      end
    end

    class << self
      # Checks if any mocks are currently registered.
      # @return [Boolean] true if mocks exist
      def mocks_active?
        MockRegistry.mocks_active?
      end

      # Retrieves the mock wrapper for a task class.
      # @param task_class [Class] The task class to look up
      # @return [MockWrapper, nil] The mock wrapper or nil if not mocked
      def mock_for(task_class)
        MockRegistry.mock_for(task_class)
      end

      # Clears all registered mocks.
      # Called automatically by test framework integrations.
      def reset_mocks!
        MockRegistry.reset!
      end
    end

    # Sets mock args for the duration of the test.
    # This allows testing code that depends on Taski.args without running full task execution.
    # Args are automatically cleared when MockRegistry.reset! is called (in test teardown).
    # @param options [Hash] User-defined options to include in args
    # @return [Taski::Args] The created args instance
    #
    # @example
    #   mock_args(env: "test", debug: true)
    #   assert_equal "test", Taski.args[:env]
    def mock_args(**options)
      Taski.reset_args!
      Taski.send(:start_args, options: options)
      Taski.args
    end

    # Sets mock env for the duration of the test.
    # This allows testing code that depends on Taski.env without running full task execution.
    # Env is automatically cleared when MockRegistry.reset! is called (in test teardown).
    # @param root_task [Class] The root task class (defaults to nil for testing)
    # @return [Taski::Env] The created env instance
    #
    # @example
    #   mock_env(root_task: MyTask)
    #   assert_equal MyTask, Taski.env.root_task
    def mock_env(root_task: nil)
      Taski.reset_env!
      Taski.send(:start_env, root_task: root_task)
      Taski.env
    end

    # Registers a mock for a task class with specified return values.
    # @param task_class [Class] A Taski::Task or Taski::Section subclass
    # @param values [Hash{Symbol => Object}] Method names mapped to return values
    # @return [MockWrapper] The created mock wrapper
    # @raise [InvalidTaskError] If task_class is not a Taski::Task/Section subclass
    # @raise [InvalidMethodError] If any method name is not an exported method
    #
    # @example
    #   mock_task(FetchData, result: { users: [1, 2, 3] })
    #   mock_task(Config, timeout: 30, retries: 3)
    def mock_task(task_class, **values)
      validate_task_class!(task_class)
      validate_exported_methods!(task_class, values.keys)

      mock_wrapper = MockWrapper.new(task_class, values)
      MockRegistry.register(task_class, mock_wrapper)
      mock_wrapper
    end

    # Asserts that a mocked task's method was accessed during the test.
    # @param task_class [Class] The mocked task class
    # @param method_name [Symbol] The exported method name
    # @return [true] If assertion passes
    # @raise [ArgumentError] If task_class was not mocked
    # @raise [Minitest::Assertion, RSpec::Expectations::ExpectationNotMetError]
    #   If method was not accessed
    def assert_task_accessed(task_class, method_name)
      mock = fetch_mock!(task_class)

      unless mock.accessed?(method_name)
        raise assertion_error("Expected #{task_class}.#{method_name} to be accessed, but it was not")
      end

      true
    end

    # Asserts that a mocked task's method was NOT accessed during the test.
    # @param task_class [Class] The mocked task class
    # @param method_name [Symbol] The exported method name
    # @return [true] If assertion passes
    # @raise [ArgumentError] If task_class was not mocked
    # @raise [Minitest::Assertion, RSpec::Expectations::ExpectationNotMetError]
    #   If method was accessed
    def refute_task_accessed(task_class, method_name)
      mock = fetch_mock!(task_class)

      if mock.accessed?(method_name)
        count = mock.access_count(method_name)
        raise assertion_error(
          "Expected #{task_class}.#{method_name} not to be accessed, but it was accessed #{count} time(s)"
        )
      end

      true
    end

    private

    def fetch_mock!(task_class)
      mock = MockRegistry.mock_for(task_class)
      return mock if mock

      raise ArgumentError, "Task #{task_class} was not mocked. Call mock_task first."
    end

    def validate_task_class!(task_class)
      valid = task_class.is_a?(Class) &&
        (task_class < Taski::Task || task_class == Taski::Task)
      return if valid

      raise InvalidTaskError,
        "Cannot mock #{task_class}: not a Taski::Task or Taski::Section subclass"
    end

    def validate_exported_methods!(task_class, method_names)
      exported = task_class.exported_methods
      method_names.each do |method_name|
        unless exported.include?(method_name)
          raise InvalidMethodError,
            "Cannot mock :#{method_name} on #{task_class}: not an exported method. Exported: #{exported.inspect}"
        end
      end
    end

    def assertion_error(message)
      # Use the appropriate assertion error class based on the test framework
      # Use fully qualified names to avoid namespace conflicts
      if defined?(::Minitest::Assertion)
        ::Minitest::Assertion.new(message)
      elsif defined?(::RSpec::Expectations::ExpectationNotMetError)
        ::RSpec::Expectations::ExpectationNotMetError.new(message)
      else
        RuntimeError.new(message)
      end
    end
  end
end

# Prepend extensions when test helper is loaded
Taski::Task.singleton_class.prepend(Taski::TestHelper::TaskExtension)
Taski::Execution::Scheduler.prepend(Taski::TestHelper::SchedulerExtension)
Taski::Execution::Executor.prepend(Taski::TestHelper::ExecutorExtension)
