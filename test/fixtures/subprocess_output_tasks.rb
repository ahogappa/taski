# frozen_string_literal: true

require "taski"

module SubprocessOutputFixtures
  class SystemSuccessTask < Taski::Task
    exports :result

    def run
      @result = system("echo hello")
    end
  end

  class SystemFailureTask < Taski::Task
    exports :result

    def run
      @result = system("exit 1")
    end
  end

  class SystemNotFoundTask < Taski::Task
    exports :result

    def run
      @result = system("nonexistent_command_xyz123")
    end
  end

  class SystemMultiArgsTask < Taski::Task
    exports :result

    def run
      @result = system("echo", "hello", "world")
    end
  end

  class SystemEnvVarsTask < Taski::Task
    exports :result

    def run
      @result = system({"TEST_VAR" => "hello_from_env"}, "echo $TEST_VAR")
    end
  end

  class SystemChdirTask < Taski::Task
    exports :result

    def run
      @result = system("pwd", chdir: "/tmp")
    end
  end

  class SystemUserOutTask < Taski::Task
    exports :result

    def run
      @result = system("echo test", out: File::NULL)
    end
  end

  class SystemEnvAndOptionsTask < Taski::Task
    exports :result

    def run
      @result = system({"MY_VAR" => "value"}, "echo $MY_VAR", chdir: "/tmp")
    end
  end
end
