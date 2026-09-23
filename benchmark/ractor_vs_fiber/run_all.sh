#!/usr/bin/env bash
# Runs the whole matrix for each Ruby given on the command line and writes one
# JSON object per line to results/<ruby-label>.jsonl.
#
#   benchmark/ractor_vs_fiber/run_all.sh ~/.rbenv/versions/4.0.7/bin/ruby ~/.rbenv/versions/4.1-dev/bin/ruby
set -euo pipefail
dir="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$dir/results"

for ruby in "$@"; do
  label="$("$ruby" -e 'print RUBY_VERSION, (RUBY_PATCHLEVEL == -1 ? "-dev" : "")')"
  out="$dir/results/$label.jsonl"
  : > "$out"
  echo "== $("$ruby" -v)" >&2
  "$ruby" "$dir/primitives.rb" --json >> "$out"
  for graph in tree wide; do
    for kind in cpu_int cpu_alloc io; do
      echo "   $graph/$kind" >&2
      "$ruby" "$dir/workload.rb" --graph "$graph" --kind "$kind" --workers 4 --repeat 5 --json >> "$out"
    done
  done
  # How the Ractor pool scales with cores on allocation-heavy work.
  for workers in 1 2 3 4; do
    "$ruby" "$dir/workload.rb" --graph wide --kind cpu_alloc --workers "$workers" --repeat 5 \
      --executors threads,taski,ractor_pool --json >> "$out"
  done
done
