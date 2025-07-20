# frozen_string_literal: true

module Taski
  # Execution context management without using Thread.current
  # Provides stack-based context tracking for build operations
  class ExecutionContext
    class << self
      # Get the current context instance
      # @return [ExecutionContext] Current context
      def current
        @current ||= new
      end

      # Reset the context (mainly for testing)
      def reset!
        @current = new
      end
    end

    def initialize
      @build_stack = []
      @analyzing_define = false
      @parent_task_stack = []
    end

    # Build stack management for circular dependency detection
    def push_build(task_class)
      @build_stack << task_class
    end

    def pop_build(task_class)
      if @build_stack.last == task_class
        @build_stack.pop
      else
        raise "Build stack corruption: expected #{task_class}, got #{@build_stack.last}"
      end
    end

    def build_stack
      @build_stack.dup
    end

    def building?(task_class)
      @build_stack.include?(task_class)
    end

    # Define analysis state management
    def analyzing_define?
      @analyzing_define
    end

    def with_analyzing_define
      previous_state = @analyzing_define
      @analyzing_define = true
      begin
        yield
      ensure
        @analyzing_define = previous_state
      end
    end

    # Parent task management for rescue_deps
    def current_parent_task
      @parent_task_stack.last
    end

    def with_parent_task(parent_task)
      @parent_task_stack << parent_task
      begin
        yield
      ensure
        @parent_task_stack.pop
      end
    end
  end
end
