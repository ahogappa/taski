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
    class << self
      def ref(klass)
        ref = Reference.new(klass)
        throw :unresolved, ref
      end

      def define(name, block, **options)
        @dependencies ||= []
        @definitions ||= {}

        class_eval(<<-RUBY, __FILE__, __LINE__ + 1)
          def self.#{name}
            __resolve__[__callee__] ||= false
            if __resolve__[__callee__]
              # already resolved
            else
              __resolve__[__callee__] = true
              throw :unresolved, [self, __callee__]
            end
          end
        RUBY

        classes = []
        loop do
          klass, task = catch(:unresolved) do
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
        @definitions[name] = { block:, options:, classes: }
      end

      def build
        resolve_dependencies.reverse.each do |task_class|
          task_class.new.build
        end
      end

      def clean
        resolve_dependencies.each do |task_class|
          task_class.new.clean
        end
      end

      def refresh
        # TODO
      end

      def resolve(queue, resolved)
        @dependencies.each do |task|
          if task[:klass].is_a?(Reference)
            task[:klass].deref
          else
            task[:klass]
          end => task_class

          # increase priority
          if resolved.include?(task_class)
            resolved.delete(task_class)
          end
          queue << task_class
        end

        # override
        class_eval(<<-RUBY, __FILE__, __LINE__ + 1)
          def self.ref(klass)
            Object.const_get(klass)
          end
        RUBY

        @definitions.each do |name, (_block, _options)|
          # override
          class_eval(<<-RUBY, __FILE__, __LINE__ + 1)
            def self.#{name}
              @__#{name} ||= @definitions[:#{name}][:block].call
            end
          RUBY

          define_method(name) do
            unless instance_variable_defined?("@__#{name}")
              instance_variable_set("@__#{name}", self.class.send(name))
            end
            instance_variable_get("@__#{name}")
          end
        end

        self
      end

      private

      def __resolve__
        @__resolve__ ||= {}
      end

      def resolve_dependencies
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
end
