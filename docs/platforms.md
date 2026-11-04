# Platforms and compatibility

The library is pure Goose. It has no external native runtime dependency beyond
Goose's standard library and the strict UTF-8 snapshot included in `vendor/`.
Applications own I/O. The API includes semantic document editing and TOML serialization. Automatic
application struct mapping is outside its scope.

## Validated configuration

- Linux x86-64, with the exact compiler revision in `GOOSE_REVISION`.
- Goose's in-process execution path and GCC native executables.
- GCC AddressSanitizer/UndefinedBehaviorSanitizer with Goose debug checks and
  bounds-check elimination disabled.
- Clang/libFuzzer with AddressSanitizer/UndefinedBehaviorSanitizer for bounded
  native fuzz campaigns.
- GitHub Actions is configured for `ubuntu-24.04`; remote run outcomes are linked
  from the public repository's Actions page rather than inferred from local runs.

Other operating systems, architectures, C compilers, and Goose revisions are not
yet validated or promised compatible. Pure Goose source alone does not establish
cross-platform support. Sanitizer/fuzzer commands currently target Linux.

## Tool prerequisites

`make setup` requires Git, CMake 3.27+, C/C++20 compilers, and Make. Linux needs
libc development headers for Goose's in-process runner. Normal UTF-8, property,
security, and vendor tests need Python 3.11+.

`make conformance` additionally builds the official runner at `TOML_TEST_REVISION`:
Go 1.27+ is needed, or an installed Go version with toolchain auto-download support
and network access. `make fuzz` requires Clang with libFuzzer, ASan, and UBSan
runtimes and the fixtures fetched by `make conformance`. `make sanitize` and the
published benchmark protocol use GCC.

Git/network access is needed to provision the pinned compiler and official test
suite. Once these tools are present, the TOML library itself does not fetch code
or access the network at runtime.

See [README.md](../README.md) for API ownership rules, exact supported syntax,
fixed resource limits, and application responsibilities.

The optional cross-language comparison harness additionally needs Rust/Cargo, Go,
and a C++17 compiler. See [its pinned setup and methodology](../bench/compare/README.md).
