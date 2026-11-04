# Third-party notices

## Vendored goose-text

The strict UTF-8 implementation in `vendor/text.goose` comes from
[carabistouflette/goose-text](https://github.com/carabistouflette/goose-text),
under Apache-2.0. Its immutable source commit and the namespace-only patch are
recorded in [vendor/README.md](vendor/README.md). Its license is preserved as
[vendor/LICENSE](vendor/LICENSE). Updating the snapshot requires provenance
verification and the full integration test suite.

## Build and test tools

Goose and the official toml-test suite are downloaded at the exact revisions in
`GOOSE_REVISION` and `TOML_TEST_REVISION`. They are external development tools,
not copied into this repository or fetched by the parser at runtime. Their own
repositories retain their licenses and notices:

- [aardappel/goose](https://github.com/aardappel/goose)
- [toml-lang/toml-test](https://github.com/toml-lang/toml-test)

Generated compiler sources, build output, downloaded test fixtures, and fuzz
corpora are excluded from the published source tree.

## Optional benchmark dependencies

The comparison harness downloads/builds external Rust `toml`
1.2.0+spec-1.1.0 (MIT OR Apache-2.0), Go BurntSushi/toml v1.6.0 (MIT),
and C++ toml++ v3.4.0 (MIT). Their source is not vendored or required at runtime.
[Dependency provenance](bench/compare/dependencies.json), Cargo.lock and go.sum
pin versions and integrity; the generated build report records transitive Rust
package license metadata. Their upstream repositories preserve full license
texts. All adapters in this repository are original Apache-2.0 code.
