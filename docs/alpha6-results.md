# Alpha.6 parsing and writing measurements

Measured documentation checkout: `6be3e2cf1c777887efed1a3fc2ad7183be8d0608`,
clean before build. Library runtime sources are byte-identical to released
**v0.1.0-alpha.6**, `e5e5644c45e78e8eb05999978bb4155ea0bbb180`.
The executable comparison harness and dependency locks match that release;
its benchmark README changed only to clarify scope. All 22 frozen audit inputs
were checked before and after the run. Final documentation changes do not
change those runtime/harness files.

## Machine and protocol

- Linux 7.2.11-arch1-1, glibc 2.44, x86-64; Intel Core Ultra 7 258V, CPU3 affinity.
- Goose `eadca409f68210893f366e60d0c2f0dc29a339be`, runtime `3025e5810379`,
  compiler executable SHA-256 `3cad45a18356bf97f4732f1da2012252afd77a652932ddb9c91c5551c04904be`.
- GCC/G++ 16.2.1; Goose standalone C at `-O2`; C++17 `-O2 -DNDEBUG`.
- Rust 1.101.0-nightly (`822182db4`), Cargo 1.101.0-nightly; release `opt-level=3`,
  16 codegen units, no LTO/debug/incremental or extra rustflags/wrappers.
- Go 1.27.3 (`X:nodwarf5`), `-mod=readonly -trimpath`, standard optimization and
  enabled default GC. Exact tool/environment records are in both raw reports.
- Rust `toml` 1.2.0+spec-1.1.0, Go BurntSushi/toml v1.6.0, C++ toml++ v3.4.0
  at `30172438cee64926dc41fdd9c11fb3ba5b2ba9de`; dependency integrity and transitive
  license/source metadata are recorded with Cargo/go locks and the build.
- Twelve fixed TOML 1.0 inputs; base 100,000 iterations divided by fixed workload
  factors. One warmup per case/runner at one tenth its measured count (minimum
  one), nine rounds, shuffled runner order with seed 20261104, `TZ=UTC`.
- One build and exactly two series. Controller UTC start
  `2026-11-05T21:18:13.238565Z`, end `21:22:50.588651Z`; 277.350 seconds including
  preflight/build/both series/cleanup. All 864 timed samples are retained.

Other project owners paused heavy local work for this finite window. This was
still a shared workstation: affinity and coordination do not prove host-wide
isolation or control CPU frequency, temperature and background services. There
was no retry, extra series, subtraction, or removal of slow samples.

## Fresh parse plus semantic walk

Each timed operation creates an owned document, consumes root count and semantic
nodes, then performs native scope cleanup. Goose walks its flat arena; the
others walk trees/maps. Untimed preflight compares actual values/types, float
bits and datetime components against Python `tomllib`. This measures these
complete public API paths, not an identical internal representation.

Cells are **median ± median absolute deviation**, in **microseconds/operation**,
from nine samples. MAD describes sample spread, not a confidence interval.
Raw reports also contain every sample, minimum, maximum and standard deviation.
No significance test or universal ranking is inferred.

| Workload | Bytes | Iterations/round | Goose | Rust | Go | C++ |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| small-config | 52 | 100000 | 0.564 ± 0.004 | 2.345 ± 0.033 | 10.148 ± 0.110 | 2.459 ± 0.046 |
| wide-table | 12780 | 1000 | 180.312 ± 3.637 | 1179.619 ± 14.548 | 2695.477 ± 69.130 | 892.862 ± 6.159 |
| float-array | 5012 | 1000 | 68.600 ± 0.732 | 434.137 ± 5.757 | 565.799 ± 10.472 | 645.865 ± 16.366 |
| escaped-strings | 3390 | 1000 | 20.277 ± 0.218 | 92.703 ± 1.764 | 264.610 ± 8.983 | 124.230 ± 4.380 |
| integer-array | 7012 | 1000 | 88.193 ± 0.891 | 371.023 ± 13.028 | 479.543 ± 9.356 | 314.154 ± 6.462 |
| long-literal | 262155 | 100 | 141.499 ± 2.554 | 362.457 ± 5.073 | 5029.356 ± 73.345 | 6858.466 ± 65.486 |
| array-then-key | 120023 | 10 | 4052.945 ± 125.668 | 22554.680 ± 385.054 | 26071.536 ± 826.793 | 7722.401 ± 93.907 |
| nested-inline-array | 120248 | 10 | 4678.090 ± 122.632 | 22935.817 ± 389.113 | 28764.684 ± 813.089 | 7757.832 ± 106.698 |
| app-server | 1521 | 1000 | 11.314 ± 0.290 | 46.898 ± 0.845 | 162.821 ± 4.380 | 70.799 ± 2.219 |
| build-project | 1771 | 1000 | 13.884 ± 0.321 | 56.992 ± 1.228 | 202.067 ± 5.295 | 78.358 ± 1.408 |
| datetime-heavy | 18124 | 1000 | 148.301 ± 2.798 | 725.050 ± 13.725 | 1708.959 ± 32.289 | 742.291 ± 15.094 |
| finite-float-range | 2888 | 1000 | 84.901 ± 1.198 | 107.168 ± 4.247 | 197.854 ± 6.191 | 265.088 ± 6.963 |

[Full parse raw report](../bench/results/2026-11-05-alpha6-full.json).

## Write an existing document

Input parsing occurs once outside timing. Each iteration creates fresh owned
output, consumes its length and edge bytes, then cleans it up. Actual outputs
are independently reparsed before timing. Default quoting, layout, ordering,
wrapping, output sizes, validation and copying differ and stay included. This
is not equal-byte formatting or allocation-normalized work.

Units and dispersion are the same as the parse table.

| Workload | Bytes | Iterations/round | Goose | Rust | Go | C++ |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| small-config | 52 | 100000 | 0.455 ± 0.005 | 0.558 ± 0.006 | 6.161 ± 0.077 | 0.756 ± 0.025 |
| wide-table | 12780 | 1000 | 119.926 ± 1.255 | 78.019 ± 1.228 | 1310.948 ± 13.651 | 122.079 ± 1.871 |
| float-array | 5012 | 1000 | 159.108 ± 0.650 | 144.692 ± 2.391 | 355.670 ± 5.615 | 542.177 ± 2.980 |
| escaped-strings | 3390 | 1000 | 13.911 ± 0.303 | 14.583 ± 0.105 | 121.953 ± 3.349 | 18.507 ± 0.414 |
| integer-array | 7012 | 1000 | 87.960 ± 2.151 | 35.398 ± 0.904 | 296.556 ± 7.752 | 65.283 ± 0.665 |
| long-literal | 262155 | 100 | 149.954 ± 3.347 | 460.850 ± 10.232 | 463.341 ± 2.888 | 1114.834 ± 23.469 |
| array-then-key | 120023 | 10 | 2755.064 ± 21.063 | 1881.665 ± 73.783 | 16898.535 ± 99.799 | 4122.739 ± 36.486 |
| nested-inline-array | 120248 | 10 | 2762.853 ± 27.869 | 1831.393 ± 28.613 | 17204.721 ± 200.531 | 4106.197 ± 14.020 |
| app-server | 1521 | 1000 | 8.487 ± 0.033 | 10.299 ± 0.133 | 90.474 ± 0.843 | 16.377 ± 0.145 |
| build-project | 1771 | 1000 | 8.911 ± 0.134 | 11.611 ± 0.154 | 110.872 ± 2.751 | 15.470 ± 0.202 |
| datetime-heavy | 18124 | 1000 | 75.159 ± 1.625 | 516.697 ± 4.356 | 1404.155 ± 12.538 | 163.030 ± 2.818 |
| finite-float-range | 2888 | 1000 | 260.149 ± 3.295 | 34.063 ± 0.944 | 86.155 ± 2.022 | 204.021 ± 7.208 |

[Write raw report](../bench/results/2026-11-05-alpha6-write.json).
All rows, including cases where Goose writing is slower, are retained. In
particular, finite-float-range writing should not be described as a speed win;
integer-array writing is also slower than Rust and C++ on this corpus.
Use the per-language output byte counts/hashes in the raw report when assessing
formatting cost. A lower median on this corpus does not predict every document.

## Limits and reproduction

These are warm-process throughput samples. Input reading/fingerprinting and
semantic preflight are outside the timers. They do not establish cold-start
latency, allocation counts, peak memory, worst-case latency or service guarantees.
Go GC work occurring during a loop is included; collection afterward is not
forced. Other runtimes retain their native storage/allocator behavior.

All timed UTC semantic checks passed. The separate, untimed Europe/Paris
check found that the pinned Go default writer changes local datetime wall
components. That discrepancy remains in both reports; those outputs are not
counted as equivalent timed writer results. This corpus uses at most six
fractional datetime digits, without leap seconds; it makes no longer-precision
or TOML 1.1 performance claim.

Use the [fixed commands](benchmarks.md#reproduce-a-new-comparison) and
[complete methodology](../bench/compare/README.md). For the exact measured source,
start with `git checkout --detach 6be3e2cf1c777887efed1a3fc2ad7183be8d0608` in a clean
clone, install the pinned dependencies, and retain new reports separately.
The [original controller report](../bench/results/2026-11-05-alpha6-controller.json)
and [controller source](../bench/results/2026-11-05-alpha6-controller.py) record
the finite run and child-group cleanup. The source identity audit remains in
[benchmark-currentness.json](benchmark-currentness.json).

[Historical reports](benchmarks.md#historical-records) retain their original
samples and caveats; these measurements do not relabel them as current.
