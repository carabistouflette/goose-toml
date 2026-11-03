# Contributing

Keep the API small, pure, and explicit. Applications own file/process I/O. Target the TOML 1.0 specification; do not silently accept later-version extensions. Add regressions for every behavior fix, including malformed input, ownership, and resource limits.

Use focused branches and Conventional Commits. Commit working milestones regularly. Run `make format`, `make check test`, and `git diff --check`. Request independent review, fix actionable findings, and keep CI passing. Do not commit generated compilers, build output, credentials, or private workspace notes.

Pin a reviewed full upstream compiler commit in `GOOSE_REVISION`. Compiler changes require full validation. No stability guarantee exists before 1.0. Report vulnerabilities privately through GitHub's advisory reporting when available.
