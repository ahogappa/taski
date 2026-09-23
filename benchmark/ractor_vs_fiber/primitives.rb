# frozen_string_literal: true

# Cost of the concurrency primitives an executor is built from: what taski pays
# today (Fiber switch, Thread::Queue hand-off) against what a Ractor-based
# executor would pay (Ractor spawn, Ractor::Port round trip, copying exports).
#
#   ruby benchmark/ractor_vs_fiber/primitives.rb [--json]
#
# Requires Ruby 4.0+ (Ractor::Port, Ractor#value).

require "json"
require_relative "support"

RESULTS = []

def bench(name, ops, repeat: 3)
  times = Array.new(repeat) do
    GC.start
    BenchSupport.measure { yield ops }
  end
  best = times.min
  RESULTS << {name: name, ops: ops, ns_per_op: best * 1e9 / ops}
end

# --- what taski uses today -------------------------------------------------

bench("fiber: new + resume", 200_000) do |n|
  n.times { Fiber.new { 1 }.resume }
end

bench("fiber: yield/resume round trip", 1_000_000) do |n|
  f = Fiber.new { loop { Fiber.yield } }
  n.times { f.resume }
end

bench("thread: new + join", 20_000) do |n|
  n.times { Thread.new { 1 }.join }
end

bench("thread: Queue round trip", 100_000) do |n|
  req = Queue.new
  res = Queue.new
  t = Thread.new { n.times { res << req.pop } }
  n.times do |i|
    req << i
    res.pop
  end
  t.join
end

# --- what a Ractor-based executor would use ---------------------------------

bench("ractor: new + value", 2_000) do |n|
  n.times { Ractor.new { 1 }.value }
end

bench("ractor: Port round trip", 100_000) do |n|
  reply = Ractor::Port.new
  r = Ractor.new(reply) do |out|
    while (v = Ractor.receive) != :stop
      out << v
    end
  end
  n.times do |i|
    r << i
    reply.receive
  end
  r << :stop
  r.join
end

# Exported values have to cross the Ractor boundary. Threads hand over a
# reference; Ractors deep-copy unless the value is shareable or moved.
def echo_ractor
  reply = Ractor::Port.new
  r = Ractor.new(reply) do |out|
    while (v = Ractor.receive) != :stop
      out << v.size # reply with something tiny so only the inbound copy is measured
    end
  end
  [r, reply]
end

MB_STRING = ("x" * (1 << 20)).freeze
HASH_10K = Array.new(10_000) { |i| ["key-#{i}", "value-#{i}"] }.to_h

bench("transfer 1MB String: Queue (ref)", 2_000) do |n|
  q = Queue.new
  n.times do
    q << MB_STRING
    q.pop
  end
end

bench("transfer 1MB String: Port copy", 2_000) do |n|
  r, reply = echo_ractor
  s = +MB_STRING # unfrozen, so it is not shareable and gets copied
  n.times do
    r << s
    reply.receive
  end
  r << :stop
  r.join
end

bench("transfer 1MB String: shareable", 2_000) do |n|
  r, reply = echo_ractor
  n.times do
    r << MB_STRING
    reply.receive
  end
  r << :stop
  r.join
end

bench("transfer Hash(10k str): Port copy", 500) do |n|
  r, reply = echo_ractor
  n.times do
    r << HASH_10K
    reply.receive
  end
  r << :stop
  r.join
end

bench("make_shareable Hash(10k str)", 500) do |n|
  n.times { Ractor.make_shareable(HASH_10K.transform_values(&:dup)) }
end

bench("  (baseline: build that Hash)", 500) do |n|
  n.times { HASH_10K.transform_values(&:dup) }
end

if ARGV.include?("--json")
  puts JSON.generate(ruby: BenchSupport.ruby_label, results: RESULTS)
else
  puts "ruby #{BenchSupport.ruby_label}"
  RESULTS.each { |r| printf("  %-36s %12.1f ns/op\n", r[:name], r[:ns_per_op]) }
end
