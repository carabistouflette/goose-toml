# Existing inline-value replacement validation

Feature checkpoint `996f6ef2e0f6f447446868fd9bf561c81784514b` adds on-demand
source-span discovery to default `put` and batch `Put`. It is **unreleased**;
alpha.4 and downstream pins stay unchanged. Engine SHA-256:
`a4c60f404996ada8780e7759b1184fafd914b820cf95d497ebf4546f0546d333`.

An enclosing inline value is reparsed through the existing key/value routines
and inline assignment framing. Its local node range is rebased and checked
against original kinds, parents and decoded keys before offsets are used.
Ordinary direct replacements retain their existing early-return path. A batch
caches discovery per enclosing inline root. Missing inline members, inline
removal, implicit dotted-table replacement and array ordinals remain unsupported.
The legacy profile never enters discovery and keeps its existing behavior.

Discovery has its own bounded parser work budget and temporary Document. It can
reject a source that passed the original index under a different hash layout.
Original source/output/path/fragment limits and terminal validation still apply;
combined node/depth/output failures return empty output. No strict allocation,
latency, or speedup claim is made.

[Structured identities and local log summaries](validation.json) record:

- Root `make format check test` passes; core/parser/writer/text/compiler files
  remain identical to alpha.4.
- Exact JIT, native optimized, and debug/no-BCE regressions for nested/quoted/
  decoded dotted keys, arrays before selected values, delimiter-like string
  bytes, multiline arrays/strings, date-times, CRLF and TOML 1.1 inline comments,
  trailing commas and version-specific escapes. Public `put` and one-edit
  `apply` return the same exact bytes.
- Full 64-inline-edit planning, same/multiple owner batches, mixed ordinary
  spans, source/value aliasing, retained final-validation errors, exact 1 MiB
  output, and combined node/depth caps. Existing unsupported legacy/removal
  cases retain their errors.
- 650 inline `put` and 778 inline batch frames in each native/debug and
  GCC/Clang ASan/UBSan mode. Python independently constructs exact output bytes
  and checks TOML 1.0 semantic trees, including types and signed zero. Explicit
  TOML 1.1 cases use exact bytes. The model does not reproduce span discovery.
- The existing 2,405 default, 533 legacy and 818 batch checks, plus 717/720
  source-index fixtures, pass. Default model expectations change only for the
  newly supported existing inline values; missing inline insertion and removal
  remain failures.
- GCC/Clang direct overload/editor tests and all models pass with ASan/UBSan,
  leak detection and UB halt enabled.
- 49,871 Clang/libFuzzer runs in 31 seconds plus the exact assertion-crash
  artifact self-test pass. Wrapped arbitrary input can introduce siblings, so
  the fuzzer checks the selected semantic value rather than assuming a fixed
  whole output. The retained local corpus affects mutation sequences. The
  existing pinned compiler emits a `frexp` alignment compilation warning;
  there was no runtime assertion or sanitizer failure.
- Independent engine and model/contract reviews found no blockers. The
  additional parse/budget cost and insertion/removal limits are documented.

[Fresh 5,134-call exact legacy parity](legacy-parity.json) reuses the clean
`cedb2c3` executable whose SHA-256 matches previously published provenance, and
an immutable companion `f8d1b166` harness with the 21 hash-verified golden cases
and 5,000 seeded generated cases. Status, output, diagnostic bytes and failure
emptiness match. Declared source/compiler/harness/fixture/executable hashes,
HEAD and clean source state were checked before and after the campaign. No
companion checkout, implementation, pin or release is changed.

Reproduce with the compiler and fixtures pinned by the root repository:

```sh
make -C source check test property conformance
make -C source sanitize SANITIZER_CC=gcc
make -C source sanitize SANITIZER_CC=clang
make -C source fuzz FUZZ_SECONDS=30 FUZZ_RUNS=100000
```

The source tests and new model run in the maintained x86/ARM CI targets.
This report records local feature evidence; exact final-head hosted checks and
publication are separate. It does not advance a release or consumer pin.
