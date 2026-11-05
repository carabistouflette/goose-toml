# Platforms and setup

The library is Goose source with a vendored UTF-8 helper. It adds no external
native runtime library and performs no I/O. Use Goose
`eadca409f68210893f366e60d0c2f0dc29a339be`, pinned in `GOOSE_REVISION`.
Other compiler revisions are not promised compatible.

## Prerequisites

`make setup` builds the pinned compiler. It needs Git/network access, Make,
CMake 3.27+, C/C++20 compilers and Linux libc development headers. Python 3.11+
is needed for property, security and vendor checks.

The optional official conformance suite needs Go 1.27+, or a Go installation
that can download that toolchain. `make conformance` fetches the runner pinned
in `TOML_TEST_REVISION`. Fuzzing needs Clang with libFuzzer, ASan and UBSan plus
the conformance fixtures. Sanitizer commands target Linux GCC/Clang.

The optional [cross-language benchmarks](../bench/compare/README.md) also need
Rust/Cargo, Go and a C++17 compiler. These are development dependencies.
The TOML library does not fetch code at runtime.

## Tested platforms

Alpha.6 CI ran natively on Linux x86-64 and ARM64, using `ubuntu-24.04` and
`ubuntu-24.04-arm`. The root and source-editor suites have different coverage:

| Suite | x86-64 | ARM64 |
| --- | --- | --- |
| Root parser/editor/writer | In-process/native tests, conformance, Python oracles, resource checks, GCC sanitizers and bounded Clang fuzzing | `check-platform.sh`: in-process/native tests, conformance, Python oracles and resource checks |
| Source-preserving editor | In-process/native tests, model/conformance, GCC **and** Clang sanitizers, bounded fuzzing, benchmark smoke | Same source-editor targets |

Root [PR](https://github.com/carabistouflette/goose-toml/actions/runs/42081027387)
and [push](https://github.com/carabistouflette/goose-toml/actions/runs/42081018140),
and source-editor [PR](https://github.com/carabistouflette/goose-toml/actions/runs/42081027407)
and [push](https://github.com/carabistouflette/goose-toml/actions/runs/42081018057)
jobs passed at release head `88502844d8b85f3b64b7e945f412cb102083dc3d`.
Its full tree matches released alpha.6 `e5e5644c45e78e8eb05999978bb4155ea0bbb180`.
Smoke execution is not a performance result. These tests do not establish
support for untested operating systems, architectures or toolchain revisions.

On a native Linux machine, reproduce the root platform gate with:

```sh
EXPECTED_ARCH=aarch64 ./scripts/check-platform.sh
# On x86-64, use EXPECTED_ARCH=x86_64 instead.
```

The script rejects a mismatched architecture or non-64-bit userspace and logs
tool/source versions. See [development commands](development.md) for the separate
source-editor and sanitizer targets. Successful runs establish the paths tested
on that platform, not exhaustive correctness.

## Runtime formatting

Integer output uses a private bounded renderer. Float fallback binds directly
to the pinned Goose runtime formatter, avoiding application overloads of global
formatting helpers. Generated C can emit an optimization-attribute redeclaration
warning for these bindings; it is retained. The compiler pin, writer-oracle,
consumer-overload and sanitizer checks cover these existing runtime functions.
This does not extend compatibility to arbitrary Goose revisions.
