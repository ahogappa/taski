# frozen_string_literal: true

require_relative "taski/version"

module Taski
  class Reference
    def initialize(klass)
      @klass = klass
    end

    def deref
      Object.const_get(@klass)
    end

    def inspect
      "&#{@klass}"
    end
  end

  class Task
    def self.__resolve__
      @__resolve__ ||= {}
    end

    def self.ref(klass)
      ref = Reference.new(klass)
      throw :unresolve, ref
    end

    def self.definition(name, block, **options)
      @dependencies ||= []
      @definitions ||= {}

      self.class_eval(<<-RUBY, __FILE__, __LINE__ + 1)
        def self.#{name}
          __resolve__[__callee__] ||= false
          if __resolve__[__callee__]
            # already resolved
          else
            __resolve__[__callee__] = true
            throw :unresolve, [self, __callee__]
          end
        end
      RUBY

      classes = []
      loop do
        klass, task = catch(:unresolve) do
          block.call
          nil
        end

        if klass.nil?
          classes.each do |task_class|
            task_class[:klass].class_eval(<<-RUBY, __FILE__, __LINE__ + 1)
              __resolve__ = {}
            RUBY
          end

          break
        else
          classes << { klass:, task: }
        end
      end

      @dependencies += classes
      @definitions[name] = {block:, options:, classes:}
    end

    def self.build
      resolve_dependences.reverse.each do |task_class|
        task_class.new.build
      end
    end

    def self.clean
      resolve_dependences.each do |task_class|
        task_class.new.clean
      end
    end

    def exec_command(command, info = nil, ret = false)
      puts "exec: #{info}" if info
      puts command

      if ret
        ret = `#{command}`.chomp
        if $?.exited?
          ret
        else
          raise "Failed to execute command: #{command}"
        end
      else
        system command, exception: true
      end
    end

    def self.refresh
      # TODO
    end

    private

    def self.resolve(queue, resolved)
      @dependencies.each do |task|
        if task[:klass].is_a?(Reference)
          task_class = task[:klass].deref
        end

        # increase priority
        if resolved.include?(task[:klass])
          resolved.delete(task[:klass])
        end
        queue << task[:klass]
      end

      # override
      self.class_eval(<<-RUBY, __FILE__, __LINE__ + 1)
        def self.ref(klass)
          Object.const_get(klass)
        end
      RUBY

      @definitions.each do |name, (block, options)|
        # override
        self.class_eval(<<-RUBY, __FILE__, __LINE__ + 1)
          def self.#{name}
            @__#{name} ||= @definitions[:#{name}][:block].call
          end
        RUBY

        self.define_method(name) do
          unless instance_variable_defined?("@__#{name}")
            instance_variable_set("@__#{name}", self.class.send(name))
          end
          instance_variable_get("@__#{name}")
        end
      end

      self
    end

    def self.resolve_dependences
      queue = [self]
      resolved = []

      while queue.any?
        resolved << task_class = queue.shift
        task_class.resolve(queue, resolved)
      end

      resolved
    end
  end
end
