# Changelog

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
