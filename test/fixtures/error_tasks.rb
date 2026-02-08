# frozen_string_literal: true

require "taski"

# Test fixtures for aggregate error and user abort tests.
module ErrorFixtures
  # Thread-safe execution tracker (replaces closure-based tracking)
  module ExecutionTracker
    @executed = []
    @mutex = Mutex.new

    class << self
      def record(task_name)
        @mutex.synchronize { @executed << task_name }
      end

      def executed
        @mutex.synchronize { @executed.dup }
      end

      def clear
        @mutex.synchronize { @executed.clear }
      end
    end
  end

  # Single failing task
  class FailingTask < Taski::Task
    exports :value

    def run
      raise "Single task failed"
    end
  end

  # Task that raises TaskAbortException
  class AbortTask < Taski::Task
    exports :value

    def run
      raise Taski::TaskAbortException, "User requested abort"
    end
  end

  # Task with custom abort message
  class AbortMessageTask < Taski::Task
    exports :data

    def run
      raise Taski::TaskAbortException, "Custom abort message"
    end
  end

  # Dependency error propagation: RootDependingOnFailingDep -> FailingDepTask
  class FailingDepTask < Taski::Task
    exports :value

    def run
      raise "Task A failed"
    end
  end

  class RootDependingOnFailingDep < Taski::Task
    exports :result

    def run
      @result = FailingDepTask.value
    end
  end

  # Dependency failure termination: RootWaitingOnDepFailure -> DepFailureTask
  class DepFailureTask < Taski::Task
    exports :value

    def run
      raise "Dependency task failed"
    end
  end

  class RootWaitingOnDepFailure < Taski::Task
    exports :result

    def run
      @result = DepFailureTask.value
    end
  end

  # Task that outputs then fails (for output capture testing)
  class OutputThenFailTask < Taski::Task
    exports :value

    def run
      puts "Step 1: Starting"
      puts "Step 2: Processing"
      puts "Step 3: About to fail"
      raise "Task failed after output"
    end
  end

  # Abort propagation: AbortPropagationDependent -> AbortPropagationSource
  class AbortPropagationSource < Taski::Task
    exports :value

    def run
      ExecutionTracker.record(:task_a)
      raise Taski::TaskAbortException, "Task A aborted"
    end
  end

  class AbortPropagationDependent < Taski::Task
    exports :result

    def run
      ExecutionTracker.record(:task_b)
      @result = AbortPropagationSource.value
    end
  end

  # Parallel failure graph:
  # ParallelFailureRoot -> [IndependentSlowTask, TaskDependingOnFailing]
  # TaskDependingOnFailing -> FailingSlowTask
  class FailingSlowTask < Taski::Task
    exports :value

    def run
      sleep 0.1
      raise "Task A failed"
    end
  end

  class IndependentSlowTask < Taski::Task
    exports :value

    def run
      sleep 0.2
      @value = "B completed"
    end
  end

  class TaskDependingOnFailing < Taski::Task
    exports :value

    def run
      @value = FailingSlowTask.value
    end
  end

  class ParallelFailureRoot < Taski::Task
    exports :result

    def run
      @result = [IndependentSlowTask.value, TaskDependingOnFailing.value]
    end
  end
end
