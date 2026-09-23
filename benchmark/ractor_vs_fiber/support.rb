# frozen_string_literal: true

# Shared helpers for the Ractor vs Fiber benchmarks. Deliberately dependency-free
# (no bundler, no benchmark-ips) so the scripts run unchanged on release and
# development Rubies that have no gems installed.

Warning[:experimental] = false

module BenchSupport
  module_function

  def now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def measure
    t0 = now
    yield
    now - t0
  end

  def median(values)
    sorted = values.sort
    mid = sorted.size / 2
    sorted.size.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2.0
  end

  def ruby_label
    "#{RUBY_VERSION}#{"-#{RUBY_REVISION[0, 10]}" if RUBY_PATCHLEVEL == -1}"
  end
end

# Task bodies used by every executor. They live in a module whose methods touch
# no unshareable state, so a non-main Ractor may call them (calling a method of
# a class owned by the main Ractor is a read, which every Ractor may do).
module Work
  module_function

  # Integer arithmetic on immediates: allocates nothing, so it isolates the
  # "GVL vs true parallelism" question from GC behaviour.
  def cpu_int(iterations)
    x = 0
    i = 0
    while i < iterations
      x = (x * 31 + i) & 0xFFFFFFFF
      i += 1
    end
    x
  end

  # Allocation-heavy work resembling ordinary Ruby code (string building,
  # arrays, hashes). This is where per-Ractor GC is supposed to matter.
  def cpu_alloc(iterations)
    acc = 0
    iterations.times do |i|
      words = Array.new(64) { |j| "item-#{i}-#{j}" }
      index = words.each_with_object({}) { |w, h| h[w] = w.upcase }
      acc += index.size
    end
    acc
  end

  # Blocking wait, standing in for subprocesses, network or disk IO. Releases
  # the GVL, so threads already overlap it.
  def io(milliseconds)
    sleep(milliseconds / 1000.0)
    milliseconds
  end

  def call(kind, param)
    case kind
    when :cpu_int then cpu_int(param)
    when :cpu_alloc then cpu_alloc(param)
    when :io then io(param)
    else raise ArgumentError, "unknown work kind: #{kind.inspect}"
    end
  end
end
