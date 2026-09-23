# frozen_string_literal: true

# Can today's Taski API be used from a non-main Ractor at all? Each probe runs
# one step of what a Ractor-based executor would have to do and prints either
# the value or the error it hit. This is a compatibility check, not a benchmark.
#
#   ruby benchmark/ractor_vs_fiber/taski_in_ractor.rb

require_relative "support"
require_relative "../../lib/taski"

Taski.progress_display = nil

class ProbeLeaf < Taski::Task
  exports :value

  def run
    @value = "leaf"
  end
end

class ProbeRoot < Taski::Task
  exports :value

  def run
    leaf = ProbeLeaf.value
    @value = "root(#{leaf})"
  end
end

# Warm every lazy per-class cache on the main Ractor first, so a probe fails
# only on what a worker Ractor would still have to do after a warm-up.
ProbeRoot.run
ProbeLeaf.cached_dependencies
ProbeRoot.cached_dependencies

# Probes are module methods rather than lambdas: a Ractor can call a method of
# a main-owned module, while a top-level lambda captures an unshareable `self`.
module Probes
  module_function

  def read_exported_methods = ProbeLeaf.exported_methods

  def read_cached_dependencies = ProbeRoot.cached_dependencies.to_a

  def instantiate_and_run = new_leaf.run

  def read_export_off_instance
    t = new_leaf
    t.run
    t.value
  end

  def leaf_run = ProbeLeaf.run

  def root_run = ProbeRoot.run

  def taski_args = Taski.args

  def new_leaf
    ProbeLeaf.allocate.tap { |t| t.__send__(:initialize) }
  end
end

PROBES = {
  "read Task.exported_methods" => :read_exported_methods,
  "read Task.cached_dependencies" => :read_cached_dependencies,
  "instantiate a task and call #run" => :instantiate_and_run,
  "read an export off that instance" => :read_export_off_instance,
  "Leaf.run (whole taski execution)" => :leaf_run,
  "Root.run (with a dependency)" => :root_run,
  "Taski.args" => :taski_args
}.freeze

puts "ruby #{BenchSupport.ruby_label}"
PROBES.each do |name, probe|
  r = Ractor.new(probe) do |m|
    Thread.current.report_on_exception = false # the error is reported below
    Probes.public_send(m)
  end
  outcome = begin
    "ok -> #{r.value.inspect}"
  rescue Ractor::RemoteError => e
    cause = e.cause
    "#{cause.class}: #{cause.message.lines.first.strip}"
  end
  printf("  %-36s %s\n", name, outcome)
end
