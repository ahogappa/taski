# frozen_string_literal: true

# Turns results/*.jsonl (written by run_all.sh) into Markdown tables.
#
#   ruby benchmark/ractor_vs_fiber/report.rb > benchmark/ractor_vs_fiber/RESULTS.md

require "json"

files = Dir[File.join(__dir__, "results", "*.jsonl")].sort
abort "no results; run run_all.sh first" if files.empty?

primitives = {}
rows = []
files.each do |f|
  File.foreach(f) do |line|
    data = JSON.parse(line, symbolize_names: true)
    if data.key?(:results)
      primitives[data[:ruby]] = data[:results].to_h { |r| [r[:name], r[:ns_per_op]] }
    else
      rows << data
    end
  end
end
rubies = (primitives.keys + rows.map { |r| r[:ruby] }).uniq

def fmt_ns(ns)
  if ns >= 1_000_000 then format("%.2f ms", ns / 1e6)
  elsif ns >= 1_000 then format("%.1f µs", ns / 1e3)
  else format("%.0f ns", ns)
  end
end

puts "## Primitives (best of 3, per operation)"
puts
puts "| operation | #{rubies.join(" | ")} |"
puts "|---|#{"---:|" * rubies.size}"
primitives.values.first.each_key do |name|
  puts "| #{name} | #{rubies.map { |rb| fmt_ns(primitives.dig(rb, name) || Float::NAN) }.join(" | ")} |"
end
puts

main = rows.select { |r| r[:workers] == 4 }.uniq { |r| r.values_at(:ruby, :graph, :kind, :executor) }
main.group_by { |r| r.values_at(:graph, :kind) }.each do |(graph, kind), group|
  tasks = group.first[:tasks]
  puts "## #{graph} (#{tasks} tasks) / #{kind} — median wall time, 4 workers (speedup vs serial)"
  puts
  puts "| executor | #{rubies.join(" | ")} |"
  puts "|---|#{"---:|" * rubies.size}"
  group.map { |r| r[:executor] }.uniq.each do |exe|
    cells = rubies.map do |rb|
      r = group.find { |x| x[:ruby] == rb && x[:executor] == exe }
      serial = group.find { |x| x[:ruby] == rb && x[:executor] == "serial" }
      next "-" unless r
      speedup = serial ? format(" (%.2fx)", serial[:median] / r[:median]) : ""
      format("%.0f ms%s", r[:median] * 1000, speedup)
    end
    puts "| #{exe} | #{cells.join(" | ")} |"
  end
  puts
end

scaling = rows.select { |r| r[:graph] == "wide" && r[:kind] == "cpu_alloc" && %w[threads taski ractor_pool].include?(r[:executor]) }
  .uniq { |r| r.values_at(:ruby, :workers, :executor) }
unless scaling.empty?
  workers = scaling.map { |r| r[:workers] }.uniq.sort
  puts "## Scaling: wide / cpu_alloc by worker count — median wall time"
  puts
  puts "| ruby | executor | #{workers.map { |w| "#{w} worker#{"s" if w > 1}" }.join(" | ")} |"
  puts "|---|---|#{"---:|" * workers.size}"
  rubies.each do |rb|
    %w[threads taski ractor_pool].each do |exe|
      cells = workers.map do |w|
        r = scaling.find { |x| x[:ruby] == rb && x[:executor] == exe && x[:workers] == w }
        r ? format("%.0f ms", r[:median] * 1000) : "-"
      end
      puts "| #{rb} | #{exe} | #{cells.join(" | ")} |"
    end
  end
end
