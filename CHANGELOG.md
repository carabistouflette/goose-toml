# Changelog

## Unreleased

- Default source `put` and batch `Put` insert missing members in inline tables,
  prepending quoted relative dotted keys while preserving existing bytes and
  trailing commas. Shared-anchor batches retain request order, including empty
  tables and shared missing prefixes. Existing limits and final validation
  apply; inline removal and legacy-profile behavior remain unchanged.

## v0.1.0-alpha.5 — 2026-11-05

- Default source `put` and batch `Put` replace existing assigned values inside
  inline tables while preserving surrounding source bytes. Each selected
  enclosing inline value is reparsed using existing parser routines; batch
  discovery is shared per owner. Legacy behavior is unchanged. Inline member
  insertion/removal, implicit dotted-table replacement and array ordinals
  remain unsupported.
- Added exact nested/quoted/dotted key, multiline, TOML 1.1, ownership, full
  64-edit and resource-limit regressions. Independent models cover 650 inline
  single edits and 778 inline batches in native/debug and GCC/Clang sanitizer
  modes; fresh 5,134-call legacy parity remains byte-identical.

Discovery adds one bounded enclosing-value parse, shared per inline owner in a
batch. Its separate parser budget can reject a source that passed the original
index under a different hash layout. Final source validation and existing caps
still apply. No new performance or allocation claim is made. See the
[inline validation report](source/tests/results/inline-replacement/README.md).
This remains an experimental prerelease without an API stability promise.

## v0.1.0-alpha.4 — 2026-11-05

- Added opt-in atomic source batches with `toml_source::Edit` and `apply`.
  Paths address the original snapshot; overlapping paths are rejected, and a
  changed batch shares its source index and final validation. Failures return
  empty output. Existing single-edit and legacy contracts remain unchanged.
- Batches permit at most 64 requests and 1 MiB aggregate decoded path/raw value
  bytes; source/output, per-path, fragment and parser limits continue to apply.
  Paths select the original snapshot, rather than a sequential dependent plan.
- Added exact ownership, full-cap, conflict, error-precedence and overload tests,
  an independent 818-case batch model, fresh 5,134-call legacy byte parity,
  GCC/Clang sanitizer coverage and bounded source fuzzing.
- Strengthened decoder/encoder oracle checks and validation-runner failure
  propagation since alpha.3. Core parser, semantic document, writer and pinned
  compiler/text sources are unchanged.

The [batch validation report](source/tests/results/atomic-batches/README.md)
retains complete paired measurements and reproduction commands. Batching helps
its independent multi-edit fixtures; the single-edit control is slower through
`apply`, so prefer `put`/`remove` for one edit. Shared-host, checksum and workload
limits apply; these results are not a universal speedup claim. This remains an
experimental prerelease without an API stability promise.

## v0.1.0-alpha.3 — 2026-11-04

- Reused the private source Document for terminal output validation after all
  source-node reads and copying finish. Public default/legacy contracts, limits,
  diagnostics, owned results and the default missing-removal fast path remain
  unchanged; core parser, document, writer and text files are unchanged.
- Added lifetime/storage-reset regressions and retained exact legacy parity,
  released-adapter alias checks, GCC/Clang sanitizer, fuzz and x86-64/ARM64
  validation evidence.

The instrumented fixture's total runtime-region count fell from 27 to 24.
These are fixture-specific runtime-region counts, not
per-call heap-allocation or universal RSS claims. Selected wide workloads repeat
timing gains; tiny/comment-heavy cases are mixed. A 9.3% large-removal outlier
failed to reproduce in the final check and remains recorded. See the
[complete report and raw controls](source/tests/results/document-reuse/README.md)
for provenance and limitations. Companion and application adoption require
separate immutable-pin validation.

## v0.1.0-alpha.2 — 2026-11-04

- Added supported `toml_source::legacy_set` and `legacy_remove` entry points for
  the companion editor's fixed-TOML-1.0 compatibility contract, using the same
  parser-driven source-edit engine as `put` and `remove`.
- Preserved existing source-editor defaults, signatures and limits. Core parser,
  semantic document, writer and vendored text files are unchanged from alpha.1.
- Verified exact legacy output and diagnostics against the clean companion
  baseline across 5,134 calls, alongside default/legacy tests, source-index
  fixtures, GCC/Clang sanitizers, fuzzing and native x86-64/ARM64 CI.

Paired default-operation measurements retained an approximately 8.5% small-removal
regression in the repeat series. Raw samples, provenance and shared-host
limitations are documented in [the source editor](source/README.md). These
measurements are workload-specific, not a universal performance guarantee.

## v0.1.0-alpha.1 — 2026-11-04

First experimental source release under Apache-2.0. APIs may change; use the
compiler pinned in `GOOSE_REVISION` and an immutable reviewed dependency commit.

- Strict TOML 1.0 parsing by default, with explicit TOML 1.1 support.
- Owned semantic document, lookup, construction, replacement, removal and compaction.
- Bounded TOML 1.0 writing, including conversion from TOML 1.1 spellings.
- Opt-in source-preserving `source/editor` put/remove operations, with owned
  results, bounded validation and byte preservation outside edited token spans.
  Inline-table children and individual array elements remain unsupported.
- Linear index-cluster audits in the fuzz harness, retaining per-node index/hash
  checks and sampled lookups without quadratic collision-key validation. A
  bounded 15-second per-input deadline accommodates the complete instrumented
  two-version roundtrip workload.
- Consumer-overload hardening for diagnostics, numeric parsing, index growth,
  owned results and numeric serialization.
- Guarded finite-float formatting improvement, independently checked against
  Python `tomllib` over 169,854 raw-bit and boundary cases.
- Native Linux x86-64 and ARM64 CI covering public APIs, both official decoder
  and encoder suites, properties, scalar oracles and hostile/resource cases.
  x86-64 additionally runs ASan/UBSan and coverage-guided fuzzing.
- Twelve-workload comparisons against pinned Rust, Go and C++ solutions, with
  raw samples, compiler/source provenance, timezone diagnostics and limitations.

Resource limits deliberately reject some valid large documents. The semantic
writer regenerates syntax; use the opt-in source editor to retain comments and
formatting outside edited spans. Automatic application struct mapping is not
provided. Writing performance remains workload-dependent, particularly for
extreme floats. See the README, platform documentation and
measured results for the complete contracts and evidence.
