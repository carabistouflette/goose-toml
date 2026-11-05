# Atomic snapshot batch validation

This is a historical feature-validation record. The named implementation is not
the complete alpha.6 implementation. See [current source API](../../../README.md)
and [benchmark status](../../../../docs/benchmarks.md); raw artifacts remain unchanged.

The `Edit`/`apply` API is included in **v0.1.0-alpha.4**. At validation time it
was unreleased. Runtime commit
`95eddfd036e7d156fe3b6ebf5693bb618d009d8a` and benchmark checkpoint
`424153d50d0c4c00b7af758fee679ed4be1bf108` have identical engine bytes:
SHA-256 `63bcce775165d33a63acb160799262bf1b4e400d34a2d6b49fcf48f4098d21f6`.
The latter changes only the benchmark harness/driver. The final evidence
checkpoint strengthens recursive Python type comparison, so booleans cannot
compare equal to integers; all 818 cases were replayed in native/debug and
both sanitizer modes after that change. The production engine is unchanged.

[Validation identities and local log summaries](validation.json) record:

- JIT, native `-O2`, and debug/no-BCE tests: exact snapshot output, shared
  anchors, CRLF, subtree/AoT removal, retained owned errors, input aliasing,
  stage precedence, actual 64 puts/removes, indexed request 63 failure, exact
  aggregate/output caps, combined depth/node limits, and hostile consumer
  `format`/`str`/`copy`/parse overloads.
- 2,405 default and 533 legacy checks plus 818 independent batch semantic,
  exact-byte/preservation and atomic-failure cases in native/debug modes.
  Python `tomllib` computes expected semantic trees independently of offsets.
- 717 TOML 1.0 and 720 TOML 1.1 source-index fixtures.
- GCC and Clang ASan/UBSan direct suites and all three models, with leak
  detection and UB halt enabled.
- 17,578 Clang/libFuzzer executions in 31 seconds, including the exact
  assertion-crash artifact self-test. The existing pinned compiler emits its
  `frexp` alignment warning while compiling; the campaign had no runtime
  assertion or sanitizer failure.
- Two independent engine/model reviews and a focused benchmark review,
  with the suggested regressions, formatting-overload hardening and benchmark
  final-transfer correction incorporated.

[Fresh legacy parity](legacy-parity.json) compares exact status, output and
error bytes against the retained clean `cedb2c3` executable in 5,134 calls,
including the 21 hash-verified frozen goldens, 5,000 seeded generated cases,
and request/fragment limits. The reference binary hash matches the previously
published clean-legacy provenance. The harness/fixture are exported from
companion `f8d1b1664a86b768a6f1375636d9b2c3a440aa31`; no companion checkout is
modified. HEAD, clean source state, declared source/compiler/harness/fixture
and executable hashes were checked before and after this separate campaign.
The shared insertion helper extraction preserves the legacy profile.

## Complete-operation measurements

[Final raw paired samples](timing-final.json) compare one `apply` against a
loop of existing `put`/`remove` calls in the **same optimized executable**.
Fixtures and requests are constructed before timing. Selected root leaves
alternate replacement and removal; the outputs are checked byte-for-byte
against independently constructed expected text before and after timing.
Sequential calls transfer intermediate results with `clear`/`append`, and
return the final result directly. Timed checks use lengths and endpoint sums,
not complete byte hashing; this checksum cannot detect every possible change.

Seven alternating pairs were run per case with pinned Goose `eadca409`,
GCC `-O2`, on Linux x86-64 CPU 3. The driver records exact commit/tree/source,
compiler executable, clean compiler checkout/stdlib manifest and benchmark
executable identities, verifying them again after measurement. This was a
shared host; other source tests ran on CPU 4 and sibling workloads could run
elsewhere. Affinity provides no exclusive-core/host or statistical guarantee.

| Fixture | Edits | Batch median µs | Sequential median µs | Batch / sequential |
| --- | ---: | ---: | ---: | ---: |
| 8 root assignments, single control | 1 | 3.013 | 2.677 | 1.125 |
| 8 root assignments | 4 | 3.060 | 9.591 | 0.319 |
| 1,024 root assignments | 16 | 417.979 | 5,715.162 | 0.073 |
| 1,024 root assignments | 64 | 612.759 | 22,779.411 | 0.027 |

Batching helps these independent multi-edit workloads. The single-edit control
is **12.5% slower** through `apply`: prefer `put`/`remove` for a single edit.
These results do not cover insertion, dependent plans, arbitrary layouts, or
old-version performance, and do not establish a universal speedup.

The [initial complete series](timing-initial.json), on CPU 4, is retained.
Its sequential loop copied even the final result into the accumulator. Review
identified that avoidable final copy; the final series uses checkpoint
`424153d` to return it directly. The initial series is not substituted for the
fairer final comparison; its single-control ratio was 1.050. CPU, shared load,
compiler-source fingerprint coverage and the harness differ between series,
so their difference cannot be attributed solely to removing that copy.

Reproduce from a clean committed checkout:

```sh
make -C source check test property conformance
make -C source sanitize SANITIZER_CC=gcc
make -C source sanitize SANITIZER_CC=clang
make -C source fuzz FUZZ_SECONDS=30 FUZZ_RUNS=100000
python3 source/tests/batch_benchmark.py --goose .toolchain/goose/build/goose \
  --cpu 3 --rounds 7 --output /tmp/atomic-batch-timings.json
```

Prior releases and downstream pins were unchanged by this feature validation.
Core parser, semantic
Document, writer and vendored text files match the approved baseline. This report records
feature validation; release identity and consumer adoption have separate evidence.
