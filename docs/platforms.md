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
- The original GitHub Actions job uses `ubuntu-24.04`; remote run outcomes are
  linked from the public repository's Actions page rather than inferred from local runs.

## Additional platform gate: Linux ARM64

CI includes a separate native `ubuntu-24.04-arm` job. It is a
[standard GitHub-hosted runner for public repositories](https://docs.github.com/en/actions/reference/runners/github-hosted-runners),
with no larger or self-hosted runner requirement. Its toolchain cache is separated
by architecture so x86-64 compiler binaries cannot be restored into the ARM job.

**The native ARM64 gate passed** at source
[`e8a605be6826f72a1031575c78b34ee1a9155a4b`](https://github.com/carabistouflette/goose-toml/commit/e8a605be6826f72a1031575c78b34ee1a9155a4b):
[actual CI execution](https://github.com/carabistouflette/goose-toml/actions/runs/41831798239).
This records execution of the checks below, rather than inferring support from
a runner label, generated C, or emulator availability.
The development workstation has QEMU/Clang but no installed ARM64 libc/sysroot or
cross compiler, so it has not produced local ARM64 execution evidence.

Reproduce the native gate on a Linux ARM64 machine with the prerequisites below:

```sh
EXPECTED_ARCH=aarch64 ./scripts/check-platform.sh
```

The script rejects a mismatched CPU architecture or non-64-bit userspace, logs
actual platform/tool versions and source/compiler revisions, then builds the
pinned compiler. It runs formatting/type checks and the public API suites through
both Goose's in-process runner and native binaries: UTF-8, parser, lifecycle,
TOML 1.1 grammar, document editing, writer/float round trips, mutation model and
example. It also runs both official TOML decoder/encoder versions, Python property
and scalar-oracle checks, and hostile/resource and encoder-protocol regressions.
Failures stop the gate. A green ARM job therefore establishes those tested paths
on that runner; it does not imply ARM sanitizer/fuzzer or benchmark validation.

Use the job's actual result at the corresponding source commit on the
[Actions page](https://github.com/carabistouflette/goose-toml/actions) as evidence.
The script also supports `EXPECTED_ARCH=x86_64` for the existing Linux target.
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
