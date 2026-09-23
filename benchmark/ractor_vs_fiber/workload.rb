# frozen_string_literal: true

# Runs the same task DAG through several executors and reports wall time.
#
#   ruby benchmark/ractor_vs_fiber/workload.rb \
#     --graph tree --kind cpu_alloc --workers 4 --repeat 5 \
#     --executors serial,threads,taski,ractor_pool,ractor_per_task [--json]
#
# Executors:
#   serial          one thread, topological order (the 1x baseline)
#   threads         push-model thread pool; no Fibers, no taski overhead
#   taski           the real Taski::Task classes (Fiber pull model on threads)
#   ractor_pool     push-model pool of worker Ractors fed through Ractor::Port
#   ractor_per_task one Ractor spawned per task once its deps are done
#
# Every task first reads its dependencies' values, then does its own work, and
# exports (work + sum of deps). The push-model executors therefore do exactly
# what taski does, minus taski's bookkeeping.
#
# Requires Ruby 4.0+ (Ractor::Port, Ractor#value).

require "json"
require "optparse"
require "tmpdir"
require_relative "support"

module BenchExec
  module_function

  # Resolve deps before working: `to_i` forces a taski lazy proxy and is a
  # no-op on the plain Integers the other executors pass in.
  def task_value(kind, param, deps)
    dep_sum = 0
    deps.each { |v| dep_sum += v.to_i }
    (Work.call(kind, param) + dep_sum) & 0xFFFFFFFF
  end
end

module Graphs
  module_function

  # Complete binary tree; node i depends on 2i+1 and 2i+2. depth 5 = 31 tasks,
  # the shape of examples/large_tree_demo.rb.
  def tree(depth)
    n = (1 << depth) - 1
    Array.new(n) { |i| [2 * i + 1, 2 * i + 2].select { |c| c < n } }
  end

  # One root fanning in `width` independent leaves.
  def wide(width)
    [(1..width).to_a] + Array.new(width) { [] }
  end
end

module Executors
  module_function

  # Every graph has deps at higher indices than their dependents, so walking
  # backwards is a valid topological order.
  def serial(graph, kind, param, _workers)
    values = Array.new(graph.size)
    (graph.size - 1).downto(0) do |i|
      values[i] = BenchExec.task_value(kind, param, graph[i].map { |d| values[d] })
    end
    values[0]
  end

  # Push-model scheduler shared by the pool executors: dispatch whatever is
  # ready, then wait for one completion at a time.
  def drive(graph, dispatch, receive)
    remaining = graph.map(&:size)
    dependents = Array.new(graph.size) { [] }
    graph.each_with_index { |deps, i| deps.each { |d| dependents[d] << i } }
    values = Array.new(graph.size)

    graph.each_index { |i| dispatch.call(i, []) if remaining[i].zero? }
    graph.size.times do
      id, value = receive.call
      values[id] = value
      dependents[id].each do |parent|
        remaining[parent] -= 1
        dispatch.call(parent, graph[parent].map { |d| values[d] }) if remaining[parent].zero?
      end
    end
    values[0]
  end

  def threads(graph, kind, param, workers)
    jobs = Queue.new
    done = Queue.new
    pool = Array.new(workers) do
      Thread.new do
        while (job = jobs.pop)
          id, deps = job
          done << [id, BenchExec.task_value(kind, param, deps)]
        end
      end
    end
    drive(graph, ->(id, deps) { jobs << [id, deps] }, -> { done.pop })
  ensure
    jobs&.close
    pool&.each(&:join)
  end

  def ractor_pool(graph, kind, param, workers)
    results = Ractor::Port.new
    pool = Array.new(workers) do |w|
      Ractor.new(results, w, kind, param) do |out, index, k, p|
        while (job = Ractor.receive) != :stop
          id, deps = job
          out << [index, id, BenchExec.task_value(k, p, deps)]
        end
      end
    end
    # Hand work only to idle workers: Ractors cannot pop from a shared queue,
    # and round-robin into per-worker inboxes would let one slow task hold up
    # everything queued behind it.
    idle = (0...workers).to_a
    backlog = []
    dispatch = lambda do |id, deps|
      if (w = idle.shift)
        pool[w] << [id, deps]
      else
        backlog << [id, deps]
      end
    end
    receive = lambda do
      w, id, value = results.receive
      if (job = backlog.shift)
        pool[w] << job
      else
        idle << w
      end
      [id, value]
    end
    drive(graph, dispatch, receive)
  ensure
    pool&.each { |r| r << :stop }
    pool&.each(&:join)
  end

  def ractor_per_task(graph, kind, param, _workers)
    results = Ractor::Port.new
    spawned = []
    dispatch = lambda do |id, deps|
      spawned << Ractor.new(results, id, deps, kind, param) do |out, i, d, k, p|
        out << [i, BenchExec.task_value(k, p, d)]
      end
    end
    drive(graph, dispatch, -> { results.receive })
  ensure
    spawned&.each(&:join)
  end

  def taski(graph, kind, param, workers)
    root = TaskiTasks.root_for(graph, kind, param)
    root.run(workers: workers)
  end
end

# Taski finds dependencies by parsing the run method's source with Prism, so
# the task classes have to exist in a real file rather than be built with
# Class.new/define_method.
module TaskiTasks
  @roots = {}

  module_function

  def root_for(graph, kind, param)
    @roots[[graph, kind, param]] ||= generate(graph, kind, param)
  end

  def generate(graph, kind, param)
    require_relative "../../lib/taski"
    Taski.progress_display = nil

    ns = "TaskiBench#{@roots.size}"
    src = +"module #{ns}\n"
    graph.each_with_index do |deps, i|
      reads = deps.each_with_index.map { |d, j| "      d#{j} = #{ns}::T#{d}.value\n" }.join
      src << "  class T#{i} < Taski::Task\n"
      src << "    exports :value\n"
      src << "    def run\n"
      src << reads
      src << "      @value = BenchExec.task_value(#{kind.inspect}, #{param}, [#{deps.each_index.map { |j| "d#{j}" }.join(", ")}])\n"
      src << "    end\n"
      src << "  end\n"
    end
    src << "end\n"

    path = File.join(Dir.mktmpdir("taski-bench"), "#{ns.downcase}.rb")
    File.write(path, src)
    require path
    Object.const_get("#{ns}::T0")
  end
end

# Sized so one task takes ~20 ms single-threaded on Ruby 4.0 (no YJIT).
DEFAULT_PARAMS = {cpu_int: 460_000, cpu_alloc: 300, io: 20}.freeze

options = {graph: "tree", kind: :cpu_alloc, workers: 4, repeat: 5, json: false,
           executors: %w[serial threads taski ractor_pool ractor_per_task], param: nil,
           depth: 5, width: 32}
OptionParser.new do |o|
  o.on("--graph NAME", %w[tree wide]) { |v| options[:graph] = v }
  o.on("--kind NAME", %w[cpu_int cpu_alloc io]) { |v| options[:kind] = v.to_sym }
  o.on("--param N", Integer) { |v| options[:param] = v }
  o.on("--depth N", Integer) { |v| options[:depth] = v }
  o.on("--width N", Integer) { |v| options[:width] = v }
  o.on("--workers N", Integer) { |v| options[:workers] = v }
  o.on("--repeat N", Integer) { |v| options[:repeat] = v }
  o.on("--executors LIST", Array) { |v| options[:executors] = v }
  o.on("--json") { options[:json] = true }
end.parse!(ARGV)

kind = options[:kind]
param = options[:param] || DEFAULT_PARAMS.fetch(kind)
graph = (options[:graph] == "tree") ? Graphs.tree(options[:depth]) : Graphs.wide(options[:width])

expected = nil
options[:executors].each do |name|
  runner = Executors.method(name)
  runner.call(graph, kind, param, options[:workers]) # warm-up: class loading, taski codegen, YJIT
  times = []
  value = nil
  options[:repeat].times do
    GC.start
    times << BenchSupport.measure { value = runner.call(graph, kind, param, options[:workers]) }
  end
  expected ||= value
  raise "#{name} computed #{value}, expected #{expected}" unless value == expected

  row = {ruby: BenchSupport.ruby_label, graph: options[:graph], tasks: graph.size, kind: kind,
         param: param, workers: options[:workers], executor: name,
         median: BenchSupport.median(times), min: times.min}
  if options[:json]
    puts JSON.generate(row)
  else
    printf("%-10s %-5s %-9s %-16s median %8.1f ms  min %8.1f ms\n",
      row[:ruby], row[:graph], row[:kind], name, row[:median] * 1000, row[:min] * 1000)
  end
end
