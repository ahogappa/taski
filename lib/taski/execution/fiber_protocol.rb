# frozen_string_literal: true

module Taski
  module Execution
    module FiberProtocol
      # === Fiber yields (task -> worker pool) ===
      StartDep = Data.define(:task_class)
      NeedDep = Data.define(:task_class, :method)

      # === Fiber resume error signal (worker pool -> task) ===
      DepError = Data.define(:error)

      # === Completion queue events (worker pool -> executor) ===
      StartDepNotify = Data.define(:task_class)
      TaskCompleted = Data.define(:task_class, :wrapper)
      TaskFailed = Data.define(:task_class, :wrapper, :error)
      CleanCompleted = Data.define(:task_class, :wrapper)
      CleanFailed = Data.define(:task_class, :wrapper, :error)

      # === Worker thread commands (pool -> worker thread) ===
      Execute = Data.define(:task_class, :wrapper)
      ExecuteClean = Data.define(:task_class, :wrapper)
      Resume = Data.define(:fiber, :value)
      ResumeError = Data.define(:fiber, :error)
    end
  end
end
