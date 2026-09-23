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

## Findings (2026-09-23)

Measured on 4 vCPUs (Intel Xeon @ 2.10GHz, Ubuntu 24.04), no YJIT, Ruby
4.0.7 against a 4.1.0dev snapshot (master `8d4efc1495`). Full tables are in
`RESULTS.md`; medians of 5 runs, 4 workers unless stated.

1. **Ruby 4.1's per-Ractor GC delivers.** On allocation-heavy work
   (`cpu_alloc`) a Ractor pool went from 1.5-1.8x over serial on 4.0.7 to
   3.6-3.7x on 4.1-dev, and scales almost linearly with workers
   (517 / 298 / 202 / 165 ms for 1-4 workers). On allocation-free work
   (`cpu_int`) Ractors were already ~3.0-3.5x on 4.0.7; 4.1 changes little.
2. **Today's executor gets no CPU parallelism on either version.** `taski` and
   the bare `threads` pool stay at 0.9-1.1x of serial on `cpu_int` and
   `cpu_alloc`: every worker thread shares the main Ractor's GVL. Against the
   bare thread pool, taski costs 1-2% on IO-bound runs and up to ~17% on
   CPU-bound ones (those runs are noisy under GVL contention).
3. **For IO-bound tasks there is nothing to gain.** With the same 4-worker cap,
   `threads`, `taski` and `ractor_pool` are within 1-2% of one another
   (~184-188 ms). `ractor_per_task` looks much faster only because it is not
   capped at 4 workers; an uncapped thread pool would do the same.
4. **Offloading inside a task already captures the gain.** `taski_offload`
   leaves taski unchanged and only wraps each task's own work in
   `Ractor.new { ... }.value`. On 4.1-dev it runs `cpu_alloc` in 155-156 ms,
   level with the dedicated Ractor pool (158-165 ms).
5. **Crossing a Ractor boundary is not free, and 4.1-dev is slower at it.**
   A small message round trip costs ~35 us on both versions, and spawning a
   Ractor 60-100 us, which is negligible next to millisecond tasks. Copying a
   large export is not: a 1 MB String costs ~0.1-0.2 ms to copy on 4.0.7 and
   ~0.5-1.0 ms on 4.1-dev (major GCs fire during the copy), a 10k-entry Hash
   2.4-2.7 ms vs 4.1-4.3 ms. Threads hand over a reference for ~0.1 us. This
   is a development snapshot, so the copy cost may still change before release.
6. **The Task API needed small changes to be read from a non-main Ractor.**
   Originally `taski_in_ractor.rb` failed on the export list and the
   dependency cache: both were unshareable class instance variables, and
   `exported_methods` even wrote `@exported_methods ||= []` while reading.
   With both made shareable and the reader no longer writing
   (`lib/taski/task.rb`), both versions now give:

   ```
   read Task.exported_methods         ok
   read Task.cached_dependencies      ok
   instantiate a task and call #run   ok
   read an export off that instance   ok
   Leaf.run / Root.run                Ractor::IsolationError (Taski::PROGRESS_MONITOR and other main-Ractor state)
   ```

   A whole execution still cannot start inside a Ractor, which a design that
   schedules on the main Ractor and moves only `#run` bodies does not need.
   4.1 tightens ownership: a class may only be modified by the Ractor that
   created it (Feature #22226), so no class-level `@x ||= ...`, in taski or in
   a user's task, can be filled from a worker Ractor.

### What this means for taski

Replacing the Thread + Fiber executor with Ractors would speed up only
CPU-bound Ruby tasks, and only if every task body were Ractor-safe. The
standard library a task typically uses works inside a Ractor on both versions
(`system`, backticks, `Open3`, `IO.popen`, File/FileUtils/Tempfile, JSON,
YAML, Digest, ERB, Timeout, threads). What breaks is shared state: unfrozen
constants (`CONFIG = {...}`), objects such as a Logger held in a constant,
class-level memoization and global variables all raise
`Ractor::IsolationError`, and an export that cannot be copied (IO, Proc,
Mutex, ...; 4.0 still copies IO and Mutex without complaint, 4.1 refuses)
cannot reach a dependent running in another Ractor. Meanwhile the
common taski workload (shelling out, network, disk) is IO-bound and already
runs in parallel on threads.

The better fit is to keep the executor and let CPU-heavy tasks offload
explicitly, which finding 4 shows already reaches Ractor-pool speed on 4.1:

```ruby
class Checksums < Taski::Task
  exports :digests

  def run
    files = FileList.paths
    @digests = Ractor.new(files) { |paths| paths.to_h { |p| [p, Digest::SHA256.file(p).hexdigest] } }.value
  end
end
```

Passing a dependency's value straight to `Ractor.new` is safe: the prestart
analyzer treats a value used as an argument as unsafe for a lazy proxy and
resolves that dependency synchronously, so the Ractor receives the real value
(`Checksums.prestart_plan` lists `FileList` under `sync`).

Inside the Ractor, `puts` goes to that Ractor's own `$stdout` and bypasses
taski's per-task output capture, and `Taski.args`/`Taski.env` must be passed
in as arguments rather than read.
