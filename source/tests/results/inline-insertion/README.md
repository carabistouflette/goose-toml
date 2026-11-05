# Missing inline-member insertion validation

This feature is included in **v0.1.0-alpha.6**. It was unreleased during the
validation recorded here. Engine checkpoint
`70fcf374569085075cec44324939a6474cf40c6c` and final alias-test checkpoint
`154dda64ab22bbb882a55d44b25165bc0f5bebe1` have identical engine bytes:
SHA-256 `d1e9c4648f1d696aa3e45ef3f976555dc1d02908c9c650a85ed85b82f22c8d4d`.
The second checkpoint only adds a regression borrowing both path and raw value
from the source and mutating that source after successful single/batch insertion.
That fixture was rerun in JIT, native, debug, GCC and Clang sanitizer modes.

Default `put` and batch `Put` prepend new entries just after the closest existing
literal inline table's opening brace, before original leading trivia. Quoted
relative dotted keys create missing prefixes or extend implicit dotted tables.
Original nonempty tables receive a trailing separator per new entry; originally
empty tables receive separators only between new entries. Same-anchor batches
retain request order. Existing bytes, including comments and trailing commas,
are preserved. Inline removal and legacy behavior remain unchanged.

[Structured identities and local log summaries](validation.json) record:

- Exact direct JIT/O2/debug tests for empty/whitespace-only tables, nested and
  implicit dotted tables, Unicode/control/empty keys, arrays, header contexts,
  CRLF, TOML 1.1 comments/trailing commas and context-invalid fragment suffixes.
  Single `put` and one-request `apply` agree byte-for-byte.
- Shared missing-prefix and same/multiple-anchor batches, mixed insertion and
  replacement, 64 actual inline insertions, invalid-fragment atomic failure,
  retained errors, source-borrowed requests, exact 1 MiB output and combined
  node/depth caps. Present inline removal and legacy insertion still fail.
- 649 insertion `put` and 777 insertion batch frames per native/debug and
  GCC/Clang ASan/UBSan mode. Expected bytes are constructed independently;
  Python `tomllib` verifies intended TOML 1.0 semantic trees with strict types.
  Explicit TOML 1.1 cases check exact bytes. The older missing-member rejection
  fixture is retained as positive insertion coverage rather than dropped.
- Existing 2,405 default, 533 legacy, 818 batch and 650/778 inline replacement
  checks pass, along with 717/720 source-index fixtures. Default expected status
  changes only for newly supported missing inline members.
- GCC/Clang direct editor/hostile-overload suites and all model adapters pass
  ASan/UBSan with leak detection and UB halt enabled.
- 18,615 Clang/libFuzzer executions in 31 seconds plus exact assertion-artifact
  self-test pass. The retained local corpus affects mutation sequences; the
  existing pinned compiler emits its `frexp` alignment compilation warning.
  There was no runtime assertion or sanitizer failure.
- Root format/check/test and independent engine/model-contract reviews pass.
  Core parser/document/writer/text/compiler remain byte-identical to alpha.5.

[Fresh 5,134-call exact legacy parity](legacy-parity.json) uses the preserved
clean `cedb2c3` executable, hash-verified golden fixtures, and immutable companion
`f8d1b166` harness. Status, output, diagnostic bytes and failure emptiness match.
Declared source/compiler/harness/fixture/binary identities, HEAD and clean state
were checked before and after at the engine checkpoint. No companion files,
working checkout, pins or release state changed.

Reproduce with the pinned compiler and official fixtures:

```sh
make -C source check test property conformance
make -C source sanitize SANITIZER_CC=gcc
make -C source sanitize SANITIZER_CC=clang
make -C source fuzz FUZZ_SECONDS=30 FUZZ_RUNS=100000
```

Discovery and final parsing retain their existing bounded budgets; this is not
a strict allocation or latency guarantee. No new performance measurement/claim,
release, consumer adoption or parent pin update is made by this feature report.
Exact final-head hosted CI and publication are separate gates.
