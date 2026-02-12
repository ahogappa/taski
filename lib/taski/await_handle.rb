# frozen_string_literal: true

module Taski
  # Eager resolution handle returned by Task.await.
  # Unlike TaskProxy (lazy), AwaitHandle resolves dependencies immediately
  # via Fiber.yield when an exported method is called.
  #
  # @example
  #   def run
  #     # Lazy (default) - resolves when the value is actually used
  #     proxy = SomeDep.value
  #
  #     # Eager - resolves immediately at this point
  #     resolved = SomeDep.await.value
  #   end
  class AwaitHandle
    def initialize(task_class)
      @task_class = task_class
    end

    def method_missing(name, *args, **kwargs, &block)
      if Thread.current[:taski_fiber_context]
        result = Fiber.yield([:need_dep, @task_class, name])
        if result.is_a?(Array) && result[0] == :_taski_error
          raise result[1]
        end
        result
      else
        @task_class.__send__(name, *args, **kwargs, &block)
      end
    end

    def respond_to_missing?(name, include_private = false)
      @task_class.respond_to?(name, include_private) || super
    end
  end
end
