# frozen_string_literal: true

require "taski"

# Task classes whose class-level state is read from a non-main Ractor.
module RactorStateFixtures
  class Leaf < Taski::Task
    exports :value

    def run
      @value = "leaf"
    end
  end

  class Extended < Leaf
    exports :extra

    def run
      super
      @extra = "extra"
    end
  end

  class Root < Taski::Task
    exports :value

    def run
      leaf = Leaf.value
      @value = "root(#{leaf})"
    end
  end

  # Entry points for the Ractor side of the test. A Ractor may call methods of
  # a module owned by the main Ractor, whereas a lambda defined here would
  # capture an unshareable self.
  module Probe
    module_function

    def exported_methods = Extended.exported_methods

    def cached_dependencies = Root.cached_dependencies.to_a

    def export_read_off_instance
      task = Leaf.allocate
      task.__send__(:initialize)
      task.run
      task.value
    end
  end
end
