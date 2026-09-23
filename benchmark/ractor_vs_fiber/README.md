# Ractor vs Fiber executor benchmarks

Taski runs every task in a Fiber on a pool of worker threads (see
`lib/taski/execution/worker_pool.rb`). All of those threads live in the main
Ractor, so they share one GVL: blocking IO overlaps, Ruby code does not. These
scripts measure what moving execution onto Ractors would buy, and what it
would cost, on Ruby 4.0 and on 4.1-dev (per-Ractor GC, class ownership).

Fiber and Ractor are not alternatives to each other: a Fiber is a coroutine
used here to park a task while its dependency runs, a Ractor is a unit of
parallelism. The comparison is therefore between executors: today's
Thread + Fiber pull model against Ractor-based pools that run the same DAG.

## Scripts

| script | what it answers |
|---|---|
| `primitives.rb` | per-operation cost of Fiber switch, Thread::Queue hand-off, Ractor spawn, Ractor::Port round trip, and copying an export across a Ractor boundary |
| `workload.rb` | wall time of one task DAG under each executor (below) |
| `taski_in_ractor.rb` | which parts of today's Taski API already work from a non-main Ractor |
| `run_all.sh` | runs the whole matrix for each Ruby passed to it, into `results/*.jsonl` |
| `report.rb` | renders `results/*.jsonl` as the tables in `RESULTS.md` |

Executors in `workload.rb`:

| executor | model |
|---|---|
| `serial` | one thread, topological order; the 1x baseline |
| `threads` | push-model pool of N threads; no Fibers and none of taski's bookkeeping |
| `taski` | the real `Taski::Task` classes run with `workers: N` |
| `taski_offload` | same taski tasks, but each task's own work runs in a Ractor it spawns and waits on |
| `ractor_pool` | push-model pool of N worker Ractors fed through `Ractor::Port` |
| `ractor_per_task` | one Ractor per task, spawned once its deps are done; not capped at N |

Graphs: `tree` is a complete binary tree of depth 5 (31 tasks, the shape of
`examples/large_tree_demo.rb`); `wide` is 32 independent leaves feeding one
root. Work kinds, each sized to ~20 ms per task on Ruby 4.0 without YJIT:
`cpu_int` (integer loop, allocates nothing), `cpu_alloc` (builds strings,
arrays and hashes), `io` (`sleep`, standing in for subprocesses and network).

## Running

```sh
benchmark/ractor_vs_fiber/run_all.sh /path/to/ruby-4.0/bin/ruby /path/to/ruby-4.1-dev/bin/ruby
ruby benchmark/ractor_vs_fiber/report.rb > benchmark/ractor_vs_fiber/RESULTS.md
ruby benchmark/ractor_vs_fiber/taski_in_ractor.rb
```

Ruby 4.0 or later is required (`Ractor::Port`, `Ractor#value`). The scripts
use no gems beyond the default/bundled `prism` and `tsort` that taski needs,
so they run on a freshly built Ruby without `bundle install`.
