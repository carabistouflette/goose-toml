# TOML feature comparison

**Historical research, 2026-11-04.** This matrix covers the semantic APIs
selected for the original comparison, not every later module. The separate
[source-preserving editor](../source/README.md) is not part of that timing scope.
 Scope assumed for implementation: **parsing and TOML writing**, including a usable mutable semantic document. This is a feature baseline, not a speed comparison or a claim of complete API parity. Only primary specifications, published package documentation, and pinned source are used below.

## Pinned comparison targets

| Target | Format support | Semantic document and TOML output | Host binding |
| --- | --- | --- | --- |
| Rust `toml` **1.2.0+spec-1.1.0** | TOML 1.1 | Owned `Table`/`Value`; mutable map/array access; `to_string`/`to_string_pretty` through Serde | Serde serialization/deserialization, including custom application types. Default features include `serde`, `parse`, `display`, `std`. [R1][R2][R3] |
| Go `BurntSushi/toml` **v1.6.0** | TOML 1.1 | Decode into mutable `map[string]any`/slices, modify, then `Marshal`/`Encoder.Encode`; no dedicated editable syntax tree | Reflection over structs/maps, field tags, custom TOML/text marshalers; metadata can identify undecoded keys. [G1][G2][G3] |
| C++ `marzer/tomlplusplus` **v3.4.0** | TOML 1.0 by default | Owned `toml::table`/`array`/typed nodes; insertion, replacement and erasure; `toml_formatter` and stream output produce TOML | Typed node access/conversion and visitors; no built-in Serde/Go-style automatic arbitrary-struct binding. [C1][C2][C3][C4] |
| goose-toml | Strict TOML 1.0 default, opt-in TOML 1.1 within fixed limits | Owned DOM; supported table/array construction, replacement and removal; bounded TOML 1.0 semantic writer | Explicit kind checks and scalar access; no automatic struct mapping. [Current API](api.md#functions-and-ownership) |

These are exact research targets, not an assertion that every target is the newest release. Rust's build metadata is part of the published version name; lock the resolved dependency graph and feature flags when reproducing comparisons. Go v1.6.0's package overview still mentions 1.0, but its pinned README and lexer/parser implement 1.1; stale overview/error-help text must not determine the supported grammar. [R3][G1][G4][G5]

## Actual common baseline

The common **format** baseline is TOML 1.0: bare/quoted/dotted keys; basic, literal and multiline strings; decimal/hex/octal/binary integers; floats including explicit infinities/NaNs; booleans; offset datetime, local datetime, local date and local time; mixed/nested arrays; normal/inline tables; arrays of tables; valid UTF-8; and rejection of invalid syntax, duplicate definitions and table/value conflicts. Comments must be accepted where the grammar permits them. TOML has no null value. [S1]

The common **document workflow** is parse → inspect → construct/modify semantic values → serialize valid TOML. Rust has mutable `Value`/map operations, Go exposes ordinary mutable maps and slices, and C++ has explicit container mutation APIs. Thus a parser-only DOM does not meet the shared library capability baseline. A writer may choose different legal string/key/table spellings: matching every input spelling is unnecessary for semantic serialization. [R1][R2][G2][G3][C2][C3][C4]

Comments/whitespace/quote style are a separate feature from accepting comments and writing TOML. The compared semantic APIs do not provide lossless source editing. Rust explicitly directs format-preserving editing to the separate `toml_edit` crate; Go discards comments in parsing; C++'s node model and formatter regenerate output. Some source flags/regions in C++ and Rust's optional insertion-order map do **not** amount to full format preservation. Goose does not need a comment-preserving editor to meet this intersection. [R4][R5][G5][C2][C4]

## TOML 1.1 versus strict 1.0

The normative changes relevant to parsing are: [S2][S3]

| Feature | Strict 1.0 | 1.1 implementation requirement |
| --- | --- | --- |
| Inline table layout | No separator newlines or trailing comma | Accept newlines, comments and trailing commas between entries, including nested inline tables. |
| Basic-string escapes | No `\e` or `\xHH` | `\e` decodes U+001B; exactly two hexadecimal digits in `\xHH` encode Unicode U+0000–U+00FF, **not an arbitrary raw byte**. Apply to quoted basic keys and multiline basic strings too. |
| Time seconds | Required | Accept `HH:MM` in local time and local/offset datetime; omitted seconds mean zero. Retain date/offset validation. |

The 1.1 changelog also clarifies dotted-key table creation, UTF-8/Unicode, multiline-literal newline normalization, precision, numeric representation choices and comment semantics. Review those against existing behavior rather than treating 1.1 as just three token changes. [S3]

Keep Goose's default strict 1.0 contract and offer explicit opt-in 1.1. Test each new spelling as accepted in 1.1 and rejected in 1.0. Emit 1.0-compatible syntax by default; any writer option emitting 1.1-only syntax must identify its target version. toml++ v3.4.0's `TOML_ENABLE_UNRELEASED_FEATURES` defaults to zero and enables only then-unreleased extensions: it is **not evidence of complete finalized 1.1 support**. [C1][C5]

## Ownership, errors and limits qualify parity

- **Ownership:** Goose owns decoded keys/string/date text; accessor views borrow the document. Edits can invalidate views; reparse/init/compact invalidate all indices. Removed subtree IDs are retired. Rust `Table`/`Value` also owns data, but its lower-level `DeValue` uses `Cow` and can borrow input. C++ tables own their nodes; Go maps/slices are runtime-managed values. Compare equivalent owned-document paths rather than treating every parse API as identical. [Current API](api.md#functions-and-ownership), [R2][R6][G2][C2]
- **Errors:** Goose returns an owned diagnostic string and may leave a partial document, which callers must discard. Rust returns `Result` with a message and optional byte span; Go has `ParseError` with position/context and separate mapping failures; C++ supports throwing `parse_error` or a nonthrowing parse-result configuration. These are materially different contracts. [Current API](api.md#functions-and-ownership), [R7][G6][C1][C6]
- **Limits:** Goose fixes input at 1 MiB, nodes at 65,536, logical depth at 64, bare scalar tokens at 128 bytes, and key-index work at 16,777,216 units. These reject otherwise valid documents. Rust's pinned parser uses a recursion guard with limit 80 unless `unbounded` is enabled; C++ defaults `TOML_MAX_NESTED_VALUES` to 256. Their counters are not interchangeable with Goose's logical depth. The inspected Go API does not expose an equivalent configurable document-budget contract; that is not a promise of unlimited safe input. [Current limits](api.md#cost-and-resource-limits), [R8][C5][G2]
- **Numeric/time representation:** Goose's i64/f64 DOM is a sensible common semantic subset, not all host-type parity: Rust's typed deserializer also handles wider integer destinations. Date/time round trips differ: Goose retains validated lexical text/fraction precision within its token cap; Go uses `time.Time` and C++ has a nanosecond field. Test precision, local-versus-offset identity, signed zero and nonfinite values explicitly; do not require byte-identical datetime spelling or NaN payload identity. [R2][R9][G5][G3][C7], [Current API](api.md#functions-and-ownership)

## Implemented baseline and validation requirements

1. **Safe construction and mutation:** `init`, `put`, `push`, `set`, `remove`, `erase` and `compact` expose supported creation/replacement/removal for table members and array elements, nested containers and every scalar kind. Keep key uniqueness, index/link/count consistency and limits valid; document view/index invalidation. Public mutable fields without invariant-preserving operations are insufficient.
2. **TOML writer:** `serialize` supports every DOM kind beneath a table root, including empty/quoted/dotted-looking keys, escaped/control characters, nested/mixed arrays, empty tables, arrays of tables, all datetime kinds, i64 boundaries, finite float round trips/signed zero and explicit `nan`/`inf`. Reject invalid constructed values/documents and report output/resource failures. A valid canonical spelling is enough; preserving the original syntax is out of scope for this baseline.
3. **Optional TOML 1.1:** `Version.V1_1` implements the grammar changes above with mode-specific validation and conformance coverage. Writing 1.0-compatible output from 1.1 input is possible by escaping differently and supplying omitted zero seconds.
4. **Evidence before claims:** validate parse/write semantic round trips and mutation invariants with boundary cases and official [toml-test](https://github.com/toml-lang/toml-test) decoder/encoder tests for the selected spec version. Test claims must name the revision, mode and limits. Typed struct binding and lossless editing remain explicit gaps relative to particular ecosystems, even after the common baseline is implemented.

There is no performance conclusion here. Feature coverage, configured limits and the measured API path must accompany any later throughput claim.

## Primary sources

- [S1] [TOML 1.0 specification](https://toml.io/en/v1.0.0).
- [S2] [TOML 1.1 specification](https://toml.io/en/v1.1.0).
- [S3] [Official changelog at TOML 1.1.0](https://github.com/toml-lang/toml/blob/1.1.0/CHANGELOG.md).
- [R1] [Rust pinned crate API](https://docs.rs/toml/1.2.0+spec-1.1.0/toml/).
- [R2] [Rust pinned Value API](https://docs.rs/toml/1.2.0+spec-1.1.0/toml/value/enum.Value.html).
- [R3] [Rust pinned Cargo manifest](https://docs.rs/crate/toml/1.2.0+spec-1.1.0/source/Cargo.toml).
- [R4] [Rust pinned README](https://docs.rs/crate/toml/1.2.0+spec-1.1.0/source/README.md).
- [R5] [Rust pinned map implementation](https://docs.rs/crate/toml/1.2.0+spec-1.1.0/source/src/map.rs).
- [R6] [Rust pinned borrowing parser values](https://docs.rs/crate/toml/1.2.0+spec-1.1.0/source/src/de/parser/devalue.rs).
- [R7] [Rust pinned error API](https://docs.rs/toml/1.2.0+spec-1.1.0/toml/de/struct.Error.html).
- [R8] [Rust pinned recursion guard configuration](https://docs.rs/crate/toml/1.2.0+spec-1.1.0/source/src/de/parser/mod.rs).
- [R9] [Rust pinned typed value deserializer](https://docs.rs/crate/toml/1.2.0+spec-1.1.0/source/src/de/deserializer/value.rs).
- [G1] [Go v1.6.0 README](https://github.com/BurntSushi/toml/blob/v1.6.0/README.md).
- [G2] [Go v1.6.0 decoding and host mapping](https://github.com/BurntSushi/toml/blob/v1.6.0/decode.go).
- [G3] [Go v1.6.0 writer](https://github.com/BurntSushi/toml/blob/v1.6.0/encode.go).
- [G4] [Go v1.6.0 lexer](https://github.com/BurntSushi/toml/blob/v1.6.0/lex.go).
- [G5] [Go v1.6.0 parser and datetime mappings](https://github.com/BurntSushi/toml/blob/v1.6.0/parse.go).
- [G6] [Go v1.6.0 diagnostic types](https://github.com/BurntSushi/toml/blob/v1.6.0/error.go).
- [C1] [toml++ v3.4.0 README](https://github.com/marzer/tomlplusplus/blob/v3.4.0/README.md).
- [C2] [toml++ v3.4.0 table API](https://github.com/marzer/tomlplusplus/blob/v3.4.0/include/toml++/impl/table.hpp).
- [C3] [toml++ v3.4.0 array API](https://github.com/marzer/tomlplusplus/blob/v3.4.0/include/toml++/impl/array.hpp).
- [C4] [toml++ v3.4.0 TOML formatter](https://github.com/marzer/tomlplusplus/blob/v3.4.0/include/toml++/impl/toml_formatter.hpp).
- [C5] [toml++ v3.4.0 feature/depth defaults](https://github.com/marzer/tomlplusplus/blob/v3.4.0/include/toml++/impl/preprocessor.hpp).
- [C6] [toml++ v3.4.0 parser implementation](https://github.com/marzer/tomlplusplus/blob/v3.4.0/include/toml++/impl/parser.inl).
- [C7] [toml++ v3.4.0 datetime representation](https://github.com/marzer/tomlplusplus/blob/v3.4.0/include/toml++/impl/date_time.hpp).
