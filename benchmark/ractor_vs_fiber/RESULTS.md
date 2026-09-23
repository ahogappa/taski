## Primitives (best of 3, per operation)

| operation | 4.0.7 | 4.1.0-8d4efc1495 |
|---|---:|---:|
| fiber: new + resume | 5.1 µs | 4.8 µs |
| fiber: yield/resume round trip | 104 ns | 107 ns |
| thread: new + join | 69.4 µs | 80.1 µs |
| thread: Queue round trip | 33.8 µs | 36.8 µs |
| ractor: new + value | 59.6 µs | 96.3 µs |
| ractor: Port round trip | 39.7 µs | 34.7 µs |
| transfer 1MB String: Queue (ref) | 114 ns | 100 ns |
| transfer 1MB String: Port copy | 212.3 µs | 980.3 µs |
| transfer 1MB String: shareable | 34.1 µs | 35.2 µs |
| transfer Hash(10k str): Port copy | 2.37 ms | 4.28 ms |
| make_shareable Hash(10k str) | 1.90 ms | 2.15 ms |
|   (baseline: build that Hash) | 789.1 µs | 797.4 µs |

## tree (31 tasks) / cpu_int — median wall time, 4 workers (speedup vs serial)

| executor | 4.0.7 | 4.1.0-8d4efc1495 |
|---|---:|---:|
| serial | 476 ms (1.00x) | 508 ms (1.00x) |
| threads | 494 ms (0.96x) | 540 ms (0.94x) |
| taski | 534 ms (0.89x) | 535 ms (0.95x) |
| ractor_pool | 158 ms (3.02x) | 157 ms (3.24x) |
| ractor_per_task | 179 ms (2.66x) | 166 ms (3.05x) |
| taski_offload | 217 ms (2.19x) | 173 ms (2.94x) |

## tree (31 tasks) / cpu_alloc — median wall time, 4 workers (speedup vs serial)

| executor | 4.0.7 | 4.1.0-8d4efc1495 |
|---|---:|---:|
| serial | 645 ms (1.00x) | 583 ms (1.00x) |
| threads | 607 ms (1.06x) | 552 ms (1.06x) |
| taski | 681 ms (0.95x) | 647 ms (0.90x) |
| ractor_pool | 422 ms (1.53x) | 158 ms (3.69x) |
| ractor_per_task | 389 ms (1.66x) | 166 ms (3.50x) |
| taski_offload | 353 ms (1.82x) | 156 ms (3.73x) |

## tree (31 tasks) / io — median wall time, 4 workers (speedup vs serial)

| executor | 4.0.7 | 4.1.0-8d4efc1495 |
|---|---:|---:|
| serial | 628 ms (1.00x) | 627 ms (1.00x) |
| threads | 184 ms (3.40x) | 184 ms (3.40x) |
| taski | 188 ms (3.34x) | 186 ms (3.37x) |
| ractor_pool | 186 ms (3.37x) | 186 ms (3.36x) |
| ractor_per_task | 105 ms (5.97x) | 106 ms (5.94x) |
| taski_offload | 195 ms (3.23x) | 195 ms (3.22x) |

## wide (33 tasks) / cpu_int — median wall time, 4 workers (speedup vs serial)

| executor | 4.0.7 | 4.1.0-8d4efc1495 |
|---|---:|---:|
| serial | 512 ms (1.00x) | 548 ms (1.00x) |
| threads | 523 ms (0.98x) | 539 ms (1.02x) |
| taski | 529 ms (0.97x) | 559 ms (0.98x) |
| ractor_pool | 150 ms (3.41x) | 155 ms (3.55x) |
| ractor_per_task | 155 ms (3.30x) | 167 ms (3.29x) |
| taski_offload | 191 ms (2.68x) | 173 ms (3.17x) |

## wide (33 tasks) / cpu_alloc — median wall time, 4 workers (speedup vs serial)

| executor | 4.0.7 | 4.1.0-8d4efc1495 |
|---|---:|---:|
| serial | 594 ms (1.00x) | 602 ms (1.00x) |
| threads | 662 ms (0.90x) | 592 ms (1.02x) |
| taski | 647 ms (0.92x) | 558 ms (1.08x) |
| ractor_pool | 327 ms (1.81x) | 165 ms (3.64x) |
| ractor_per_task | 398 ms (1.49x) | 152 ms (3.95x) |
| taski_offload | 363 ms (1.64x) | 155 ms (3.89x) |

## wide (33 tasks) / io — median wall time, 4 workers (speedup vs serial)

| executor | 4.0.7 | 4.1.0-8d4efc1495 |
|---|---:|---:|
| serial | 667 ms (1.00x) | 667 ms (1.00x) |
| threads | 183 ms (3.64x) | 183 ms (3.64x) |
| taski | 186 ms (3.59x) | 186 ms (3.60x) |
| ractor_pool | 186 ms (3.59x) | 186 ms (3.58x) |
| ractor_per_task | 42 ms (15.75x) | 44 ms (15.28x) |
| taski_offload | 193 ms (3.45x) | 195 ms (3.42x) |

## Scaling: wide / cpu_alloc by worker count — median wall time

| ruby | executor | 1 worker | 2 workers | 3 workers | 4 workers |
|---|---|---:|---:|---:|---:|
| 4.0.7 | threads | 624 ms | 664 ms | 687 ms | 662 ms |
| 4.0.7 | taski | 666 ms | 720 ms | 756 ms | 647 ms |
| 4.0.7 | ractor_pool | 687 ms | 494 ms | 372 ms | 327 ms |
| 4.1.0-8d4efc1495 | threads | 594 ms | 678 ms | 598 ms | 592 ms |
| 4.1.0-8d4efc1495 | taski | 636 ms | 620 ms | 542 ms | 558 ms |
| 4.1.0-8d4efc1495 | ractor_pool | 517 ms | 298 ms | 202 ms | 165 ms |
