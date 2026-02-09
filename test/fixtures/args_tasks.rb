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

  # Task that captures working directory
  class WorkingDirectoryTask < Taski::Task
    exports :captured_dir

    def run
      @captured_dir = Taski.env.working_directory
      CapturedValues.store(:working_directory, @captured_dir)
    end
  end

  # Task that captures started_at
  class StartedAtTask < Taski::Task
    exports :captured_time

    def run
      @captured_time = Taski.env.started_at
      CapturedValues.store(:started_at, @captured_time)
    end
  end

  # Task that captures root_task
  class RootTaskCaptureTask < Taski::Task
    exports :value

    def run
      CapturedValues.store(:root_task, Taski.env.root_task)
      @value = "test"
    end
  end

  # Task that captures args and env references
  class ArgsAndEnvCaptureTask < Taski::Task
    exports :value

    def run
      CapturedValues.store(:captured_args, Taski.args)
      CapturedValues.store(:captured_env, Taski.env)
      @value = "test"
    end
  end

  # Task that captures Taski.args[:env]
  class ArgsOptionsCaptureTask < Taski::Task
    exports :env_value

    def run
      @env_value = Taski.args[:env]
      CapturedValues.store(:args_env, @env_value)
    end
  end

  # Task that captures Taski.args[:nonexistent]
  class ArgsMissingKeyCaptureTask < Taski::Task
    exports :missing_value

    def run
      @missing_value = Taski.args[:nonexistent]
      CapturedValues.store(:args_missing, @missing_value)
    end
  end

  # Task that captures Taski.args.fetch(:timeout, 30)
  class ArgsFetchDefaultTask < Taski::Task
    exports :timeout_value

    def run
      @timeout_value = Taski.args.fetch(:timeout, 30)
      CapturedValues.store(:fetch_default, @timeout_value)
    end
  end

  # Task that captures Taski.args.fetch(:computed) { 10 * 5 }
  class ArgsFetchBlockTask < Taski::Task
    exports :computed_value

    def run
      @computed_value = Taski.args.fetch(:computed) { 10 * 5 }
      CapturedValues.store(:fetch_block, @computed_value)
    end
  end

  # Task that captures Taski.args.fetch(:timeout, 30) with existing value
  class ArgsFetchExistingTask < Taski::Task
    exports :timeout_value

    def run
      @timeout_value = Taski.args.fetch(:timeout, 30)
      CapturedValues.store(:fetch_existing, @timeout_value)
    end
  end

  # Task that captures key?() results
  class ArgsKeyCheckTask < Taski::Task
    exports :has_env, :has_missing

    def run
      @has_env = Taski.args.key?(:env)
      @has_missing = Taski.args.key?(:missing)
      CapturedValues.store(:has_env, @has_env)
      CapturedValues.store(:has_missing, @has_missing)
    end
  end

  # Task that captures args reference for immutability test
  class ArgsImmutabilityTask < Taski::Task
    exports :result

    def run
      CapturedValues.store(:args_ref, Taski.args)
      @result = Taski.args[:env]
    end
  end
end
