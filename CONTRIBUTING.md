# Contributing

Keep the API small, pure, and explicit. Applications own file/process I/O. Keep TOML 1.0 strict by default and test TOML 1.1 only through the explicit version option. The writer emits TOML 1.0-compatible syntax. Add regressions for every behavior fix, including malformed input, ownership, and resource limits.

Use focused branches and Conventional Commits. Commit working milestones regularly. Run `make format`, `make check test`, and `git diff --check`. Request independent review, fix actionable findings, and keep CI passing. Do not commit generated compilers, build output, credentials, or private workspace notes.

Pin a reviewed full upstream compiler commit in `GOOSE_REVISION`. Compiler changes require full validation. No stability guarantee exists before 1.0. Report vulnerabilities through the private process in [SECURITY.md](SECURITY.md).

For behavior or vendored-source changes, also run `make conformance property
scalar writer-scalar security sanitize fuzz`. Optional fuzz campaigns need Clang and its sanitizer
runtimes; see [development commands](docs/development.md). Preserve immutable vendor provenance and licenses.
Measure performance changes with the same workload source, pinned compiler and
C compiler flags; retain raw samples and report any regressions and limitations.

Open a focused pull request against `main` and describe the changed behavior,
relevant contract/limit changes, and exact checks run. Do not publish generated
binaries, toolchains or fuzz corpora. Security-sensitive inputs belong in private
reports until a coordinated fix is ready.
