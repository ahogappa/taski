# frozen_string_literal: true

require "monitor"

module Taski
  module Execution
    # Producer-Consumer pattern executor for parallel task execution.
    #
    # Executor is the orchestrator that coordinates all execution components.
    #
    # == Architecture
    #
    #   Executor
    #     ├── Scheduler: Dependency management and execution order
    #     ├── WorkerPool: Thread management and task distribution
    #     └── ExecutionContext: Observer notifications and output capture
    #             └── Observers (e.g., TreeProgressDisplay)
    #
    # == Execution Flow
    #
    # 1. Build dependency graph via Scheduler
    # 2. Set up progress display via ExecutionContext
    # 3. Start WorkerPool threads
    # 4. Enqueue ready tasks (no dependencies) to WorkerPool
    # 5. Run event loop:
    #    - Pop completion events from workers
    #    - Mark completed in Scheduler
    #    - Enqueue newly ready tasks to WorkerPool
    # 6. Shutdown WorkerPool when root task completes
    # 7. Teardown progress display
    #
    # == Communication Queues
    #
    # - Execution Queue (Main -> Worker): Tasks ready to execute (via WorkerPool)
    # - Completion Queue (Worker -> Main): Events from workers
    #
    # == Thread Safety
    #
    # - Main Thread: Manages all state, coordinates execution, handles events
    # - Worker Threads: Execute tasks and send completion events (via WorkerPool)
    class Executor
      class << self
        # Execute a task and all its dependencies
        # @param root_task_class [Class] The root task class to execute
        # @param registry [Registry] The task registry
        ##
        # Create a new Executor and run execution for the specified root task class.
        # @param root_task_class [Class] The top-level task class to execute.
        # @param registry [Taski::Registry] Registry providing task definitions and state.
        # @param execution_context [ExecutionContext, nil] Optional execution context to use; when nil a default context is created.
        # @return [Object] The result returned by the execution of the root task.
        def execute(root_task_class, registry:, execution_context: nil)
          new(registry: registry, execution_context: execution_context).execute(root_task_class)
        end

        # Execute clean for a task and all its dependencies (in reverse order)
        # @param root_task_class [Class] The root task class to clean
        # @param registry [Registry] The task registry
        ##
        # Runs reverse-order clean execution beginning at the given root task class.
        # @param [Class] root_task_class - The root task class whose dependency graph will drive the clean run.
        # @param [Object] registry - Task registry used to resolve and track tasks during execution.
        # @param [ExecutionContext, nil] execution_context - Optional execution context for observers and output capture; if `nil`, a default context is created.
        def execute_clean(root_task_class, registry:, execution_context: nil)
          new(registry: registry, execution_context: execution_context).execute_clean(root_task_class)
        end
      end

      ##
      # Initialize an Executor and its internal coordination components.
      # @param [Object] registry - Task registry used to look up task definitions and state.
      # @param [Integer, nil] worker_count - Optional number of worker threads to use; when `nil` the WorkerPool default is used.
      # @param [Taski::Execution::ExecutionContext, nil] execution_context - Optional execution context for observers and output capture; when `nil` a default context (with progress observer and execution trigger) is created.
      def initialize(registry:, worker_count: nil, execution_context: nil)
        @registry = registry
        @completion_queue = Queue.new

        # ExecutionContext for observer pattern and output capture
        @execution_context = execution_context || create_default_execution_context

        # Scheduler for dependency management
        @scheduler = Scheduler.new

        # WorkerPool for thread management
        @worker_pool = WorkerPool.new(
          registry: @registry,
          worker_count: worker_count
        ) { |task_class, wrapper| execute_task(task_class, wrapper) }
      end

      # Execute root task and all dependencies
      ##
      # Execute the task graph rooted at the given task class.
      #
      # Builds the dependency graph, starts progress reporting and worker threads,
      # enqueues tasks that are ready (no unmet dependencies), and processes worker
      # completion events until the root task finishes. After completion or abort,
      # shuts down workers, stops progress reporting, and restores stdout capture if
      # this executor configured it.
      # @param root_task_class [Class] The root task class to execute.
      def execute(root_task_class)
        # Build dependency graph from static analysis
        @scheduler.build_dependency_graph(root_task_class)

        # Set up progress display with root task
        setup_progress_display(root_task_class)

        # Set up output capture (returns true if this executor set it up)
        should_teardown_capture = setup_output_capture_if_needed

        # Start progress display
        start_progress_display

        # Start worker threads
        @worker_pool.start

        # Enqueue tasks with no dependencies
        enqueue_ready_tasks

        # Main event loop - continues until root task completes
        run_main_loop(root_task_class)

        # Shutdown workers
        @worker_pool.shutdown

        # Stop progress display
        stop_progress_display

        # Restore original stdout (only if this executor set it up)
        teardown_output_capture if should_teardown_capture
      end

      # Execute clean for root task and all dependencies (in reverse dependency order)
      # Clean operations run in reverse: root task cleans first, then dependencies
      ##
      # Executes the clean workflow for the given root task in reverse dependency order.
      # Sets up progress display and optional output capture, starts a dedicated clean worker pool,
      # enqueues ready-to-clean tasks, processes completion events until all tasks are cleaned,
      # then shuts down workers and tears down progress and output capture as needed.
      # @param [Class] root_task_class - The root task class to clean
      def execute_clean(root_task_class)
        # Build reverse dependency graph for clean order
        @scheduler.build_reverse_dependency_graph(root_task_class)

        # Set up progress display with root task (if not already set)
        setup_progress_display(root_task_class)

        # Set up output capture (returns true if this executor set it up)
        should_teardown_capture = setup_output_capture_if_needed

        # Start progress display
        start_progress_display

        # Create a new worker pool for clean operations
        @clean_worker_pool = WorkerPool.new(
          registry: @registry,
          worker_count: nil
        ) { |task_class, wrapper| execute_clean_task(task_class, wrapper) }

        # Start worker threads
        @clean_worker_pool.start

        # Enqueue tasks ready for clean (no reverse dependencies)
        enqueue_ready_clean_tasks

        # Main event loop - continues until all tasks are cleaned
        run_clean_main_loop(root_task_class)

        # Shutdown workers
        @clean_worker_pool.shutdown

        # Stop progress display
        stop_progress_display

        # Restore original stdout (only if this executor set it up)
        teardown_output_capture if should_teardown_capture
      end

      private

      # Enqueue all tasks that are ready to execute
      def enqueue_ready_tasks
        @scheduler.next_ready_tasks.each do |task_class|
          enqueue_task(task_class)
        end
      end

      # Enqueue a single task for execution
      def enqueue_task(task_class)
        return if @registry.abort_requested?

        @scheduler.mark_enqueued(task_class)

        wrapper = get_or_create_wrapper(task_class)
        return unless wrapper.mark_running

        @execution_context.notify_task_registered(task_class)
        @execution_context.notify_task_started(task_class)

        @worker_pool.enqueue(task_class, wrapper)
      end

      # Get or create a task wrapper via Registry
      def get_or_create_wrapper(task_class)
        @registry.get_or_create(task_class) do
          task_instance = task_class.allocate
          task_instance.send(:initialize)
          TaskWrapper.new(task_instance, registry: @registry, execution_context: @execution_context)
        end
      end

      # Execute a task and send completion event (called by WorkerPool)
      def execute_task(task_class, wrapper)
        return if @registry.abort_requested?

        output_capture = @execution_context.output_capture

        # Start capturing output for this task
        output_capture&.start_capture(task_class)

        # Set thread-local execution context for task access (e.g., Section)
        ExecutionContext.current = @execution_context

        begin
          result = wrapper.task.run
          wrapper.mark_completed(result)
          @completion_queue.push({task_class: task_class, wrapper: wrapper})
        rescue Taski::TaskAbortException => e
          @registry.request_abort!
          wrapper.mark_failed(e)
          @completion_queue.push({task_class: task_class, wrapper: wrapper, error: e})
        rescue => e
          wrapper.mark_failed(e)
          @completion_queue.push({task_class: task_class, wrapper: wrapper, error: e})
        ensure
          # Stop capturing output for this task
          output_capture&.stop_capture
          # Clear thread-local execution context
          ExecutionContext.current = nil
        end
      end

      # Main thread event loop - continues until root task completes
      def run_main_loop(root_task_class)
        until @scheduler.completed?(root_task_class)
          break if @registry.abort_requested? && !@scheduler.running_tasks?

          event = @completion_queue.pop
          handle_completion(event)
        end
      end

      ##
      # Marks the given task as completed in the scheduler and enqueues any tasks that become ready as a result.
      # @param [Hash] event - Completion event containing information about the finished task.
      # @param [Class] event[:task_class] - The task class that completed.
      def handle_completion(event)
        task_class = event[:task_class]

        debug_log("Completed: #{task_class}")

        @scheduler.mark_completed(task_class)

        # Enqueue newly ready tasks
        enqueue_ready_tasks
      end

      # ========================================
      # Clean Execution Methods
      # ========================================

      ##
      # Enqueues all tasks that are currently ready to be cleaned.
      def enqueue_ready_clean_tasks
        @scheduler.next_ready_clean_tasks.each do |task_class|
          enqueue_clean_task(task_class)
        end
      end

      ##
      # Enqueues a single task for reverse-order (clean) execution.
      # If execution has been aborted, does nothing. Marks the task as clean-enqueued,
      # skips if the task is not registered or not eligible to run, notifies the
      # execution context that cleaning has started, and schedules the task on the
      # clean worker pool.
      # @param [Class] task_class - The task class to enqueue for clean execution.
      def enqueue_clean_task(task_class)
        return if @registry.abort_requested?

        @scheduler.mark_clean_enqueued(task_class)

        wrapper = @registry.get_task(task_class)
        return unless wrapper
        return unless wrapper.mark_clean_running

        @execution_context.notify_clean_started(task_class)

        @clean_worker_pool.enqueue(task_class, wrapper)
      end

      ##
      # Executes the clean lifecycle for a task and emits a completion event.
      #
      # Runs the task's `clean` method, measures its duration in milliseconds, updates the provided
      # wrapper with success or failure, notifies the execution context of completion (including
      # duration and any error), and pushes a completion event onto the executor's completion queue.
      # This method respects an abort requested state from the registry (no-op if abort already requested)
      # and triggers a registry abort when a `Taski::TaskAbortException` is raised.
      # It also starts and stops per-task output capture when available and sets the thread-local
      # `ExecutionContext.current` for the duration of the clean.
      # @param [Class] task_class - The task class being cleaned.
      # @param [Taski::Execution::TaskWrapper] wrapper - The wrapper instance for the task, used to record clean success or failure.
      def execute_clean_task(task_class, wrapper)
        return if @registry.abort_requested?

        output_capture = @execution_context.output_capture

        # Start capturing output for this task
        output_capture&.start_capture(task_class)

        # Set thread-local execution context for task access
        ExecutionContext.current = @execution_context

        start_time = Time.now
        begin
          result = wrapper.task.clean
          duration_ms = ((Time.now - start_time) * 1000).round(1)
          wrapper.mark_clean_completed(result)
          @execution_context.notify_clean_completed(task_class, duration: duration_ms)
          @completion_queue.push({task_class: task_class, wrapper: wrapper, clean: true})
        rescue Taski::TaskAbortException => e
          @registry.request_abort!
          duration_ms = ((Time.now - start_time) * 1000).round(1)
          wrapper.mark_clean_failed(e)
          @execution_context.notify_clean_completed(task_class, duration: duration_ms, error: e)
          @completion_queue.push({task_class: task_class, wrapper: wrapper, error: e, clean: true})
        rescue => e
          duration_ms = ((Time.now - start_time) * 1000).round(1)
          wrapper.mark_clean_failed(e)
          @execution_context.notify_clean_completed(task_class, duration: duration_ms, error: e)
          @completion_queue.push({task_class: task_class, wrapper: wrapper, error: e, clean: true})
        ensure
          # Stop capturing output for this task
          output_capture&.stop_capture
          # Clear thread-local execution context
          ExecutionContext.current = nil
        end
      end

      ##
      # Runs the main event loop that processes clean completion events until all tasks have been cleaned.
      # Continuously pops events from the internal completion queue and delegates them to the clean completion handler,
      # stopping early if an abort is requested and no clean tasks are running.
      # @param [Class] root_task_class - The root task class that defines the overall clean lifecycle.
      def run_clean_main_loop(root_task_class)
        # Find all tasks in the dependency graph
        # Continue until all tasks have been cleaned
        until all_tasks_cleaned?
          break if @registry.abort_requested? && !@scheduler.running_clean_tasks?

          event = @completion_queue.pop
          handle_clean_completion(event)
        end
      end

      ##
      # Processes a clean completion event and advances the cleaning workflow.
      # Marks the completed task in the scheduler and enqueues any tasks that become ready to clean.
      # @param [Hash] event - A completion event hash containing the `:task_class` key for the task that finished cleaning.
      def handle_clean_completion(event)
        task_class = event[:task_class]

        debug_log("Clean completed: #{task_class}")

        @scheduler.mark_clean_completed(task_class)

        # Enqueue newly ready clean tasks
        enqueue_ready_clean_tasks
      end

      ##
      # Determines whether all tasks have finished their clean phase.
      # @return [Boolean] `true` if there are no ready-to-clean tasks and no running clean tasks, `false` otherwise.
      def all_tasks_cleaned?
        @scheduler.next_ready_clean_tasks.empty? && !@scheduler.running_clean_tasks?
      end

      # Notify observers about the root task
      # @param root_task_class [Class] The root task class
      # @return [void]
      def setup_progress_display(root_task_class)
        @execution_context.notify_set_root_task(root_task_class)
      end

      # Set up output capture if progress display is active and not already set up
      # @return [Boolean] true if this executor set up the capture
      def setup_output_capture_if_needed
        return false unless Taski.progress_display
        return false if @execution_context.output_capture_active?

        @execution_context.setup_output_capture($stdout)
        true
      end

      # Tear down output capture and restore original $stdout
      # @return [void]
      def teardown_output_capture
        @execution_context.teardown_output_capture
      end

      def start_progress_display
        @execution_context.notify_start
      end

      def stop_progress_display
        @execution_context.notify_stop
      end

      def create_default_execution_context
        context = ExecutionContext.new
        progress = Taski.progress_display
        context.add_observer(progress) if progress

        # Set execution trigger to break circular dependency with TaskWrapper
        context.execution_trigger = ->(task_class, registry) do
          Executor.execute(task_class, registry: registry, execution_context: context)
        end

        context
      end

      def debug_log(message)
        return unless ENV["TASKI_DEBUG"]
        puts "[Executor] #{message}"
      end
    end
  end
end
