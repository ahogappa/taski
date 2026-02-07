# frozen_string_literal: true

require "taski"

# Test fixtures for args tests.
module ArgsFixtures
  # Thread-safe value capture (replaces closure-based capturing)
  module CapturedValues
    @values = {}
    @mutex = Mutex.new

    class << self
      def store(key, value)
        @mutex.synchronize { @values[key] = value }
      end

      def get(key)
        @mutex.synchronize { @values[key] }
      end

      def get_all(key)
        @mutex.synchronize { @values[key] }
      end

      def clear
        @mutex.synchronize { @values.clear }
      end
    end
  end

  # Dependency pair for root_task consistency test
  class DepTask < Taski::Task
    exports :value

    def run
      CapturedValues.store(:dep_root, Taski.env.root_task)
      @value = "dep"
    end
  end

  class RootConsistencyTask < Taski::Task
    exports :value

    def run
      CapturedValues.store(:root_before, Taski.env.root_task)
      DepTask.value
      CapturedValues.store(:root_after, Taski.env.root_task)
      @value = "root"
    end
  end

  # Dependency pair for env value consistency test
  class EnvCaptureDep < Taski::Task
    exports :value

    def run
      CapturedValues.store(:dep_env, {
        root: Taski.env.root_task,
        dir: Taski.env.working_directory,
        time: Taski.env.started_at
      })
      @value = "dep"
    end
  end

  class EnvCaptureRoot < Taski::Task
    exports :value

    def run
      CapturedValues.store(:root_env, {
        root: Taski.env.root_task,
        dir: Taski.env.working_directory,
        time: Taski.env.started_at
      })
      EnvCaptureDep.value
      @value = "root"
    end
  end

  # Dependency pair for args sharing test
  class ArgsDepTask < Taski::Task
    exports :dep_value

    def run
      CapturedValues.store(:dep_env_arg, Taski.args[:env])
      @dep_value = "from_dep"
    end
  end

  class ArgsMainTask < Taski::Task
    exports :main_value

    def run
      @main_value = ArgsDepTask.dep_value
    end
  end
end
