# Historical source-editor validation and timing

These records describe the revisions named in each section. Their editor
implementations differ from alpha.6; they are not current alpha.6 timing claims.
Raw artifacts, slower results and original caveats are preserved. See the
[current guide](../README.md) and [benchmark status](../../docs/benchmarks.md).

## Compatibility-profile validation and timing

The new profile has 21 exact legacy output/diagnostic fixtures from clean
companion `cedb2c3`, plus 512 independent root/header insertion byte checks.
`source/tests/legacy-contract.json` retains the original fixture bytes and reference
revision. The oracle also transports arbitrary path bytes as hex, including
NUL and paths above the operating system's argument-size limit. JIT, optimized
native and debug tests cover exact 1 MiB output, sixfold reservation, path and
combined parser limits, UTF-8/suffix precedence and hostile consumer overloads.
The existing 2,405 default model checks and 717/720 source-index fixtures remain
separate acceptance checks. Wrapper output clearing and aliasing must also be
validated by the companion's own public-API tests before adoption.

Engine `04c8bef` passed two independent code reviews, GCC/Clang ASan/UBSan,
and 35,688 Clang/libFuzzer executions in a 31-second bounded campaign, including
the assertion-artifact self-test. An independent
[5,134-call differential](../tests/results/legacy-parity-04c8bef.json) against clean
`cedb2c3` compared exact status, output, diagnostic bytes and failure emptiness,
with Python `tomllib` independently checking successful outputs. Its frozen
candidate checkout, executable and source hashes were verified before and after
the campaign. This is canonical-engine evidence; companion/consumer adoption
has separate gates. The earlier `5cca023` evidence does not cover optimization
`04c8bef`; the reported final differential does.

[Paired default-operation raw samples and provenance](../tests/results/default-profile-04c8bef.json)
compare alpha `b59b25a` with engine `04c8bef`, using the unchanged four-case
benchmark, pinned Goose `eadca409`, GCC 16.2.1 and `-O2`, on Linux x86-64 CPU 0.
One warmup per build precedes nine alternating pairs of 1,000 operations.
All calls create fresh parser state and owned output, including validation.
The ratios of candidate/baseline medians were **1.005** (put small), **1.085**
(remove small), **0.983** (put large) and **0.953** (remove large). The small
removal regression remains; these samples do not establish a universal speedup.
This was a shared host, with local GCC tests overlapping on CPU 2 during part
of the series. Source/binary identities and all samples are retained; readable
compiler identity and fixture-length consistency were verified after timing,
as disclosed in the report. The earlier pre-optimization series is also
[retained without dropping regressions](../tests/results/default-profile-initial.json).

To repeat the historical comparison, use the immutable baseline/candidate
revisions and harness hashes recorded in the linked report. For a new experiment,
freeze both sources and the shared harness before running:

```sh
python3 source/tests/compare_profiles.py /path/to/baseline /path/to/candidate \
  --goose /path/to/pinned/goose --cpu 0 --rounds 9 --iterations 1000 \
  --output /tmp/default-profile.json
```

The current driver additionally checks its own fingerprint, compiler identity
and fixture lengths during the run. Its earlier measured revision is recorded
in the report; the subsequent changes tighten provenance only. Performance of
the actual thin wrapper must be measured independently against its frozen
legacy implementation before publishing companion performance claims.

## Recorded complete-operation timings

[Raw samples and provenance](../results/2026-11-04-linux-x86_64.json) were measured
from clean source commit `c9359f380f420ac7c055d9caad1ef20a20c9dccd` after the
parser consumer-overload hardening in parent
`c32c7dab44883f8fb5a5a984bf6f3c4c49119d79`. The checkout used an external
matching compiler through `GOOSE`; no toolchain symlink or tracked edits were
present. The driver fingerprints sources before compilation and verifies them
again before and after timing. The report includes compiler/hardware/flags,
source and binary hashes, every fixture and seven raw samples after one warmup.

Command: `make -C source bench CC=gcc BENCH_ITERATIONS=100`, on Linux x86-64,
Intel Core Ultra 7 258V, GCC 16.2.1, `-O2`, CPU affinity 0. These are complete
fresh operations, including all parsing, copying, allocation and validation;
input construction occurs outside the measured loops. Other processes may run
on the development machine; no exclusive-host or cross-library claim is made.

| Operation | Input bytes | Median ns/operation |
| --- | ---: | ---: |
| put_small | 68 | 2617.6 |
| remove_small | 68 | 1174.1 |
| put_large | 289072 | 1773086.4 |
| remove_large | 289072 | 1595069.2 |

The large fixture contains 256 KiB of commentary and 1,000 dependency entries.
These cases characterize specific workloads; they do not prove worst-case
latency or a universal performance ranking. CI runs benchmark smoke execution
without timing thresholds.

The recorded pre-profile local source validation also passed the consumer-overload regression
in-process and optimized native, all model/fixture checks under the hardened
parser, GCC/Clang ASan/UBSan, and 84,695 Clang/libFuzzer executions in 31 seconds
(seed 20261104, bounded by the 30-second budget). The assertion-bridge self-test
verified exact crash-artifact capture. That execution count is a recorded
campaign, not an exhaustive input claim. No source I/O or manifest publication
was performed by the module.
