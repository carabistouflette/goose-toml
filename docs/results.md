# Measured results and validation

## Parser snapshot

Measurements below use parser commit
[`9e8e4bcfbd227ed206cf59594d0ce329d5ebfb86`](https://github.com/carabistouflette/goose-toml/commit/9e8e4bcfbd227ed206cf59594d0ce329d5ebfb86),
with vendored goose-text `09d5f0c39e50d3270189bd0c6798cd10ab2f0c0d`.
This is a historical parser-only measurement. Subsequent feature and performance
changes are not represented by these samples. Exact source-file, workload, tool and
binary hashes are in the [raw report](../bench/results/2026-11-04-linux-x86_64.json).

## Native benchmark, 2026-11-04 UTC

This is an absolute measurement of this snapshot, not a comparison against
another parser, another language, or an earlier release.

- Platform: Linux-7.2.11-arch1-1-x86_64-with-glibc2.44.
- CPU: Intel(R) Core(TM) Ultra 7 258V (one allowed CPU pinned by the harness).
- Compiler: Goose eadca409f68210893f366e60d0c2f0dc29a339be; gcc (GCC) 16.2.1 20260810; GCC `-O2` native build.
- Python: 3.14.9.
- Protocol: one unrecorded full warm-up, nine recorded rounds, monotonic timer,
  destination reuse inside each timed loop. Input construction occurs outside
  timing; parsed-node checksums are consumed and checked across rounds.

| Workload | Input bytes | Parses per round | Median microseconds per parse |
| --- | ---: | ---: | ---: |
| small config | 52 | 100,000 | 0.498 |
| wide table | 12,780 | 1,000 | 171.291 |
| float array | 5,012 | 1,000 | 67.277 |
| escaped strings | 3,390 | 1,000 | 19.710 |
| integer array | 7,012 | 1,000 | 89.101 |
| long literal | 262,155 | 100 | 470.310 |
| array then key | 120,023 | 10 | 3465.679 |
| nested inline array | 120,248 | 10 | 4137.297 |

The report retains every sample, iteration count, checksum, binary digest, and
measurement command. Timing occurred on a shared developer workstation. CPU
frequency, scheduling, compiler versions, data shape and destination reuse affect
these results. Large workloads deliberately use fewer iterations per round.
These measurements do not establish cold-start latency, allocation counts,
service-level guarantees or machine-independent throughput. No "fastest" or
security conclusion follows from them.

Reproduce with the same source and toolchain:

```sh
make setup
.toolchain/goose/build/goose build bench/parse.goose --cc gcc -O2 -o .build/publication-bench
python3 scripts/benchmark.py --candidate .build/publication-bench --iterations 100000 --repeats 9 --output .build/publication-results.json
```

Use `--baseline /path/to/another-bench` only after building both versions with
the same benchmark source and compiler flags. Paired comparisons randomize run
order and retain both sets of samples. Build directories can affect generated
binary hashes; bit-identical executables are not promised across environments.

## Correctness and resource checks

The reviewed parser snapshot passes all 208 valid and 509 invalid official TOML
1.0 decoder cases (no skips), 2,000 deterministic property/mutation documents,
272 hostile/resource documents including real hash-collision budget rejection,
and GCC ASan/UBSan checks. In-process and native suites cover ownership, Unicode,
limit boundaries, declaration states and recovery after partial failures.
The integrated UTF-8 snapshot also has dedicated in-process/native regressions.

Bounded coverage-guided fuzzing checks structural invariants and memory safety,
not an independent semantic oracle. Campaign execution counts depend on the
retained corpus and time budget; they are not a coverage percentage. Reproduce
validation with:

```sh
make format check test conformance property security sanitize
make fuzz
```

Provisioning and test dependencies are documented in
[platforms.md](platforms.md). Public CI runs are available under
[GitHub Actions](https://github.com/carabistouflette/goose-toml/actions).
Passing checks and independent reviews provide evidence, not exhaustive
correctness or a formal security guarantee.
