# frozen_string_literal: true

module Taski
  # Lazy proxy that defers dependency resolution until the value is actually used.
  # Inherits from BasicObject to minimize available methods, maximizing method_missing delegation.
  class TaskProxy < BasicObject
    def initialize(task_class, method)
      @task_class = task_class
      @method = method
      @resolved = false
      @value = nil
      @error = nil
    end

    def __resolve__
      ::Kernel.raise @error if @error
      return @value if @resolved
      @value = ::Fiber.yield([:need_dep, @task_class, @method])
      if @value.is_a?(::Array) && @value[0] == :_taski_error
        @error = @value[1]
        ::Kernel.raise @error
      end
      @resolved = true
      @value
    end

    def __taski_proxy_resolve__
      __resolve__
    end

    def method_missing(name, *args, **kwargs, &block)
      __resolve__.__send__(name, *args, **kwargs, &block)
    end

    def respond_to_missing?(name, include_private = false)
      name == :__taski_proxy_resolve__ || __resolve__.respond_to?(name, include_private)
    end

    def !
      !__resolve__
    end

    def ==(other)
      __resolve__ == other
    end

    def !=(other)
      __resolve__ != other
    end

    def equal?(other)
      __resolve__.equal?(other)
    end

    def respond_to?(name, include_private = false)
      name == :__taski_proxy_resolve__ || __resolve__.respond_to?(name, include_private)
    end
  end
end
