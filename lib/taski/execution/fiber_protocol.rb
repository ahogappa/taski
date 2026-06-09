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

      # === request_value outcome (TaskWrapper -> WorkerPool#handle_dependency) ===
      # How a NeedDep should be resolved, based on the dependency's current state.
      DepCompleted = Data.define(:value) # already done; resume immediately with value
      DepFailed = Data.define(:error)    # already failed; propagate the error
      DepWaiting = Data.define           # running; caller parked, resumed via its queue
      DepStarting = Data.define          # was pending, now running; caller must drive it

      # === handle_dependency outcome (worker pool internal) ===
      # Tells drive_fiber_loop how to proceed after resolving a NeedDep.
      ResumeWith = Data.define(:value) # resume the parent fiber with this value
      Parked = Data.define # parent fiber parked (or a nested dep is being driven)

      # === Worker thread commands (pool -> worker thread) ===
      Execute = Data.define(:task_class, :wrapper)
      ExecuteClean = Data.define(:task_class, :wrapper)
      Resume = Data.define(:fiber, :value)
      ResumeError = Data.define(:fiber, :error)
    end
  end
end
