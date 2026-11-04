# Changelog

## v0.1.0-alpha.1 — 2026-11-04

First experimental source release under Apache-2.0. APIs may change; use the
compiler pinned in `GOOSE_REVISION` and an immutable reviewed dependency commit.

- Strict TOML 1.0 parsing by default, with explicit TOML 1.1 support.
- Owned semantic document, lookup, construction, replacement, removal and compaction.
- Bounded TOML 1.0 writing, including conversion from TOML 1.1 spellings.
- Consumer-overload hardening for diagnostics, numeric parsing, index growth,
  owned results and numeric serialization.
- Guarded finite-float formatting improvement, independently checked against
  Python `tomllib` over 169,854 raw-bit and boundary cases.
- Native Linux x86-64 and ARM64 CI covering public APIs, both official decoder
  and encoder suites, properties, scalar oracles and hostile/resource cases.
  x86-64 additionally runs ASan/UBSan and coverage-guided fuzzing.
- Twelve-workload comparisons against pinned Rust, Go and C++ solutions, with
  raw samples, compiler/source provenance, timezone diagnostics and limitations.

Resource limits deliberately reject some valid large documents. Serialization
regenerates syntax; comments/formatting and automatic application struct mapping
are not preserved/provided. Writing performance remains workload-dependent,
particularly for extreme floats. See the README, platform documentation and
measured results for the complete contracts and evidence.
