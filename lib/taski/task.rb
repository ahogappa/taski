# frozen_string_literal: true

require "stringio"
require_relative "static_analysis/analyzer"
require_relative "execution/registry"
require_relative "execution/task_wrapper"
require_relative "progress/layout/tree"
require_relative "progress/theme/plain"
require_relative "task_proxy"

module Taski
  # Base class for all tasks in the Taski framework.
  # Tasks define units of work with dependencies and exported values.
  #
  # @example Defining a simple task
  #   class MyTask < Taski::Task
  #     exports :result
  #
  #     def run
  #       @result = "completed"
  #     end
  #   end
  class Task
    class << self
      ##
      # Callback invoked when a subclass is created.
      # Automatically creates a task-specific Error class for each subclass.
      # @param subclass [Class] The newly created subclass.
      def inherited(subclass)
        super
        # Create TaskClass::Error that inherits from Taski::TaskError
        error_class = Class.new(Taski::TaskError)
        subclass.const_set(:Error, error_class)
      end

      ##
      # Declares exported methods that will be accessible after task execution.
      # Exported values are resolved lazily through method_missing, so an export
      # never overrides an existing method (Module#name, Task.run, ...) — it is
      # only reachable as +Task.method+ / +instance.method+ when no method of
      # that name already exists. Colliding names are warned about here.
      # @param export_methods [Array<Symbol>] The method names to export.
      def exports(*export_methods)
        names = export_methods.map(&:to_sym)
        names.each do |name|
          warn_export_collision(name) if export_name_collides?(name)
        end
        # Accumulate so repeated `exports` calls add to, rather than clobber,
        # the set. method_missing resolves names as Symbols, so normalize here.
        @exported_methods = (@exported_methods || []) | names
      end

      ##
      # Whether an export name is already a method (so the accessor won't be
      # reachable). Checks public + private, on the class (singleton) and on
      # instances, but ignores the generic Module/Class/Object/Kernel methods
      # every class has, so we only warn about real collisions (Ruby/Taski public
      # API and user-/Taski-defined private methods).
      def export_name_collides?(method)
        singleton_class.method_defined?(method) ||
          method_defined?(method) ||
          (singleton_class.private_method_defined?(method) && !Class.private_method_defined?(method)) ||
          (private_method_defined?(method) && !Object.private_method_defined?(method))
      end

      ##
      # Returns the list of exported method names, including those inherited from
      # parent task classes. Resolution (method_missing) and several internal
      # consumers gate on this list, so it must walk the ancestor chain — a
      # subclass that inherits exports without re-declaring them still resolves
      # them, and a subclass adding an export keeps the inherited ones.
      # @return [Array<Symbol>] The exported method names.
      def exported_methods
        own = (@exported_methods ||= [])
        inherited = superclass.respond_to?(:exported_methods) ? superclass.exported_methods : []
        inherited | own
      end

      ##
      # Resolves an exported value when called as Task.<export> on the class.
      # Only fires for names that are not already defined as real methods, so an
      # export can never shadow Module#name / Task.run / etc.
      def method_missing(name, *args, **kwargs, &block)
        # Resolve only a known export, and only for a valid call shape: no
        # positional args and at most the `args:` keyword. Anything else falls
        # through to super so a malformed call fails like a normal method instead
        # of silently resolving and dropping the arguments.
        if exported_methods.include?(name) && args.empty? && (kwargs.keys - [:args]).empty?
          resolve_exported_value(name, kwargs.fetch(:args, {}))
        else
          super
        end
      end

      def respond_to_missing?(name, include_private = false)
        exported_methods.include?(name) || super
      end

      private :new

      ##
      # Returns cached static dependencies for this task class.
      # Dependencies are analyzed from the run method body using static analysis.
      # @return [Set<Class>] The set of task classes this task depends on.
      def cached_dependencies
        @dependencies_cache ||= StaticAnalysis::Analyzer.analyze(self)
      end

      ##
      # Clears the cached dependency analysis for this class.
      # Useful when task code has changed and dependencies need to be re-analyzed.
      # Invalidates every per-class memo: the dependency set, the circular-check
      # result (so a newly-introduced cycle is caught), and the StartDepAnalyzer
      # prestart cache.
      def clear_dependency_cache
        @dependencies_cache = nil
        @circular_dependency_checked = false
        StaticAnalysis::StartDepAnalyzer.clear_cache_for(self)
      end

      ##
      # Executes the task and all its dependencies.
      # Creates a fresh registry each time for independent execution.
      # @param args [Hash] User-defined arguments accessible via Taski.args.
      # @param workers [Integer, nil] Number of worker threads for parallel execution.
      #   Must be a positive integer or nil.
      #   Use workers: 1 for sequential execution (useful for debugging).
      # @param profile [true, IO, nil] When set, print a timing report (per-task
      #   start offsets, durations, critical path) after the run — to $stdout
      #   for +true+, or to the given IO. Purely observational; the return value
      #   is unchanged.
      # @raise [ArgumentError] If workers is not a positive integer or nil.
      # @return [Object] The result of task execution.
      def run(args: {}, workers: nil, profile: nil)
        execution = -> { with_execution_setup(args: args, workers: workers) { |wrapper| wrapper.run } }
        return execution.call unless profile

        report = Taski.profile { execution.call }
        write_profile_report(report, profile)
        report.result
      end

      ##
      # Execute run followed by clean in a single operation.
      # By default, clean is skipped when run fails.
      # Use clean_on_failure: true to always execute clean for resource release.
      # An optional block is executed between run and clean phases.
      #
      # @param args [Hash] User-defined arguments accessible via Taski.args.
      # @param workers [Integer, nil] Number of worker threads for parallel execution.
      #   Must be a positive integer or nil.
      # @param clean_on_failure [Boolean] When true, clean runs even if run raises (default: false).
      # @raise [ArgumentError] If workers is not a positive integer or nil.
      # @return [Object] The result of task execution
      # @yield Optional block executed between run and clean phases
      def run_and_clean(args: {}, workers: nil, clean_on_failure: false, profile: nil, &block)
        execution = -> { with_execution_setup(args: args, workers: workers) { |wrapper| wrapper.run_and_clean(clean_on_failure: clean_on_failure, &block) } }
        return execution.call unless profile

        report = Taski.profile { execution.call }
        write_profile_report(report, profile)
        report.result
      end

      ##
      # Resets the task state and progress display.
      # Useful for testing or re-running tasks from scratch.
      def reset!
        Taski.reset_args!
        Taski.reset_progress_display!
        @circular_dependency_checked = false
      end

      ##
      # Renders a static tree representation of the task dependencies.
      # When Taski.prestart_debug is true, appends a per-task prestart plan.
      # @return [String] The rendered tree string.
      def tree
        output = StringIO.new
        theme = Progress::Theme::Plain.new
        layout = Progress::Layout::Tree.build(output: output, theme: theme)
        context = Execution::ExecutionFacade.new(root_task_class: self)
        layout.context = context
        layout.on_ready
        rendered = layout.render_tree
        return rendered unless Taski.prestart_debug

        rendered + prestart_debug_annotation(context)
      end

      ##
      # The prestart plan for this task: which dependencies are speculatively
      # prestarted (lazy proxy / IO overlap), which are resolved synchronously,
      # and where phase-1 stopped scanning the run body. Inspection aid for the
      # otherwise-invisible prestart heuristic; does not run the task.
      # @return [Hash] {task:, prestarted: [names], sync: [names], stopped_at: {line:, source:} | nil}
      def prestart_plan
        analysis = StaticAnalysis::StartDepAnalyzer.analyze(self)
        {
          task: name || inspect,
          prestarted: analysis.start_deps.map { |c| c.name || c.inspect }.sort,
          sync: analysis.sync_deps.map { |c| c.name || c.inspect }.sort,
          stopped_at: analysis.stopped_at && {line: analysis.stopped_at.line, source: analysis.stopped_at.source}
        }.freeze
      end

      private

      ##
      # Build the prestart-plan annotation appended to Task.tree under
      # Taski.prestart_debug. One line per task that actually has a plan.
      def prestart_debug_annotation(context)
        graph = context.dependency_graph
        tasks = graph.respond_to?(:all_tasks) ? graph.all_tasks : [self]
        lines = ([self] + tasks).uniq.filter_map do |task_class|
          next unless task_class.respond_to?(:prestart_plan)
          plan = task_class.prestart_plan
          next if plan[:prestarted].empty? && plan[:sync].empty? && plan[:stopped_at].nil?

          parts = ["#{plan[:task]}:"]
          parts << "prestart=#{plan[:prestarted].inspect}" unless plan[:prestarted].empty?
          parts << "sync=#{plan[:sync].inspect}" unless plan[:sync].empty?
          parts << "stopped@#{plan[:stopped_at][:line]}" if plan[:stopped_at]
          "  #{parts.join(" ")}"
        end
        return "" if lines.empty?

        "\nprestart plan:\n#{lines.join("\n")}\n"
      end

      ##
      # Write a profile report to the destination given as the +profile:+
      # option: $stdout for +true+, otherwise the given IO-like object.
      def write_profile_report(report, destination)
        io = destination.respond_to?(:puts) ? destination : $stdout
        io.puts(report)
      end

      ##
      # Sets up execution environment and yields a fresh wrapper.
      # Handles workers validation, args lifecycle, and dependency validation.
      # @param args [Hash] User-defined arguments
      # @param workers [Integer, nil] Number of worker threads
      # @yield [wrapper] Block receiving the fresh wrapper to execute
      # @return [Object] The result of the block
      def with_execution_setup(args:, workers:)
        validate_workers!(workers)
        Taski.send(:with_env, root_task: self) do
          Taski.send(:with_args, options: args.merge(_workers: workers)) do
            validate_no_circular_dependencies!
            yield fresh_wrapper
          end
        end
      end

      ##
      # Creates a fresh TaskWrapper with its own registry.
      # Used for class method execution (Task.run) where each call is independent.
      # @return [Execution::TaskWrapper] A new wrapper with fresh registry.
      def fresh_wrapper
        fresh_registry = Execution::Registry.new
        task_instance = allocate
        task_instance.__send__(:initialize)
        wrapper = Execution::TaskWrapper.new(
          task_instance,
          registry: fresh_registry,
          execution_facade: Execution::ExecutionFacade.current
        )
        fresh_registry.register(self, wrapper)
        wrapper
      end

      ##
      # Warn that an export name collides with an existing method. Resolution
      # goes through method_missing, which only fires for *undefined* names, so a
      # public method of the same name shadows the export (the method wins) while
      # a private one leaves resolution ambiguous (an external call reaches the
      # export, an internal one the private method). Either way the name is
      # unreliable, so warn.
      # @param method [Symbol] The colliding export name.
      def warn_export_collision(method)
        warn "Taski: #{self} exports :#{method}, but a method named :#{method} already exists. " \
          "An existing method can take precedence over the export, so #{self}.#{method} " \
          "(and instance ##{method}) may not return the exported value. " \
          "Choose a different export name to avoid the ambiguity."
      end

      ##
      # Resolve an exported value for a Task.<export> call.
      # When called inside an execution, returns the cached value from the
      # registry (or a proxy / synchronous Fiber pull during the run phase).
      # When called outside execution, creates a fresh execution.
      # @param method [Symbol] The exported method name.
      # @param args [Hash] User-defined arguments (only honored outside execution).
      def resolve_exported_value(method, args)
        registry = Taski.current_registry
        if registry
          unless args.empty?
            warn "Taski: args: passed to #{self}.#{method} is ignored inside an execution context"
          end
          if Thread.current[:taski_fiber_context]
            start_deps = Thread.current[:taski_start_deps]
            if start_deps&.include?(self)
              # Lazy resolution via proxy - safe dep confirmed by static analysis
              TaskProxy.new(self, method)
            else
              # Synchronous resolution: dep not in allowlist (unknown or unsafe usage)
              result = Fiber.yield(Taski::Execution::FiberProtocol::NeedDep.new(self, method))
              raise result.error if result in Taski::Execution::FiberProtocol::DepError
              result
            end
          else
            # Synchronous resolution (clean phase, outside Fiber)
            wrapper = registry.get_or_create(self) do
              task_instance = allocate
              task_instance.__send__(:initialize)
              Execution::TaskWrapper.new(
                task_instance,
                registry: registry,
                execution_facade: Execution::ExecutionFacade.current
              )
            end
            wrapper.get_exported_value(method)
          end
        else
          # Outside execution - fresh execution (top-level call)
          Taski.send(:with_env, root_task: self) do
            Taski.send(:with_args, options: args) do
              validate_no_circular_dependencies!
              fresh_wrapper.get_exported_value(method)
            end
          end
        end
      end

      ##
      # Validates that no circular dependencies exist in the task graph.
      # @raise [Taski::CircularDependencyError] If circular dependencies are detected.
      def validate_no_circular_dependencies!
        return if @circular_dependency_checked

        graph = StaticAnalysis::DependencyGraph.new.build_from(self)
        cyclic_components = graph.cyclic_components

        if cyclic_components.any?
          raise Taski::CircularDependencyError.new(cyclic_components)
        end

        @circular_dependency_checked = true
      end

      ##
      # Validates the workers parameter.
      # @param workers [Object] The workers parameter to validate.
      # @raise [ArgumentError] If workers is not a positive integer or nil.
      def validate_workers!(workers)
        return if workers.nil?

        unless workers.is_a?(Integer) && workers >= 1
          raise ArgumentError, "workers must be a positive integer or nil, got: #{workers.inspect}"
        end
      end
    end

    ##
    # Executes the task's main logic.
    # Subclasses must override this method to implement task behavior.
    # @raise [NotImplementedError] If not overridden in a subclass.
    def run
      raise NotImplementedError, "Subclasses must implement the run method"
    end

    ##
    # Cleans up resources after task execution.
    # Override in subclasses to implement cleanup logic.
    def clean
    end

    # Override system() to capture subprocess output through the pipe-based architecture.
    # Uses Kernel.system with :out option to redirect output to the task's pipe.
    # If user provides :out or :err options, they are respected (no automatic redirection).
    # @param args [Array] Command arguments (shell mode if single string, exec mode if array)
    # @param opts [Hash] Options passed to Kernel.system
    # @return [Boolean, nil] true if command succeeded, false if failed, nil if command not found
    def system(*args, **opts)
      write_io = $stdout.respond_to?(:current_write_io) ? $stdout.current_write_io : nil

      if write_io && !opts.key?(:out)
        # Redirect subprocess output to the task's pipe (stderr merged into stdout)
        Kernel.system(*args, out: write_io, err: [:child, :out], **opts)
      else
        # No capture active or user provided custom :out, use normal system
        Kernel.system(*args, **opts)
      end
    end

    # Groups related output within a task for organized progress display.
    # The group name is shown in the progress tree as a child of the task.
    # Groups cannot be nested.
    #
    # @param name [String] The group name to display
    # @yield The block to execute within the group
    # @return [Object] The result of the block
    # @raise Re-raises any exception from the block after marking group as failed
    #
    # @example
    #   def run
    #     group("Preparing") do
    #       puts "Checking dependencies..."
    #       puts "Validating config..."
    #     end
    #     group("Deploying") do
    #       puts "Uploading files..."
    #     end
    #   end
    def group(name)
      context = Execution::ExecutionFacade.current
      phase = Thread.current[:taski_current_phase] || :run
      context&.notify_group_started(self.class, name, phase: phase, timestamp: Time.now)

      begin
        result = yield
        context&.notify_group_completed(self.class, name, phase: phase, timestamp: Time.now)
        result
      rescue
        context&.notify_group_completed(self.class, name, phase: phase, timestamp: Time.now)
        raise
      end
    end

    ##
    # Resets the instance's exported values to nil.
    def reset!
      self.class.exported_methods.each do |method|
        instance_variable_set("@#{method}", nil)
      end
    end

    ##
    # Reads an exported value (instance.<export>). Only fires for export names
    # that are not already defined as real instance methods, so an export can
    # never shadow an existing method.
    def method_missing(name, *args, &block)
      # Resolve a known export only when called with no arguments (Ruby folds a
      # trailing keyword hash into *args too); otherwise fall through to super so
      # a malformed call fails fast.
      if self.class.exported_methods.include?(name) && args.empty?
        instance_variable_get("@#{name}")
      else
        super
      end
    end

    def respond_to_missing?(name, include_private = false)
      self.class.exported_methods.include?(name) || super
    end
  end
end
