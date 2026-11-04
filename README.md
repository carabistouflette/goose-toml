# goose-toml

A pure [Goose](https://github.com/aardappel/goose) TOML 1.0 document parser. Apache-2.0. Experimental API; no release yet. No runtime dependencies beyond the Goose standard library. Strict UTF-8 validation and scalar encoding use a pinned, vendored goose-text snapshot (see [vendor/README.md](vendor/README.md)).

Supports bare, quoted and dotted keys; all four string forms; signed 64-bit integers in decimal/hex/octal/binary; binary64 floats including explicit `inf`/`nan`; booleans; date/time values; mixed and nested arrays; tables; inline tables; and arrays of tables. Targets [TOML 1.0](https://toml.io/en/v1.0.0), with the resource limits below. TOML 1.1 extensions are rejected.

## Quick start

```sh
git clone https://github.com/carabistouflette/goose-toml.git
cd goose-toml
make setup check test
.toolchain/goose/build/goose run examples/config.goose
```

This builds the pinned compiler and runs the included example from a standalone
clone. See [platforms and prerequisites](docs/platforms.md) before setup.
The example in `examples/config.goose` uses:

```goose
import toml from "..";  // from an example in this checkout
import std;

fn main() {
    var doc = toml::Document { .. };
    let error = toml::parse_into("[server]\nport = 8080\n", doc);
    if error.len > 0 { print(error); return; }
    let server = toml::find(doc, 0, "server");
    let port = toml::find(doc, server, "port");
    if port >= 0 && doc.nodes[port].kind == toml::Kind.Integer {
        print(doc.nodes[port].integer);
    }
}
```

From a nearby project use `import toml from "../goose-toml";`, adjusting the local path. For a remote dependency use
`import toml from "carabistouflette/goose-toml@<full-published-commit>";`,
replacing the placeholder with the full commit you have reviewed. There are no
tagged releases or stability promises yet. Applications own file/process I/O. This first API parses a document; struct mapping and serialization are outside its scope.

## API and ownership

- `valid_utf8(bytes)` is a supported allocation-free strict UTF-8 check. It accepts Unicode scalars including NUL, BOM and noncharacters; TOML syntax restrictions apply separately during parsing.
- `parse_into(text, doc)` returns an owned error string, empty on success. It replaces the destination, including on failure. On error the document may be partial: discard it. Messages identify a zero-based byte offset and one-based line/byte column, except input-size and UTF-8 preflight failures, which report byte 0.
- Create the destination as `var doc = toml::Document { .. };`. It is a `root struct` because it owns several independently growable arenas; Goose root structs cannot be returned by value.
- Root is node `0` on success. Nodes use integer indices, which remain valid during arena growth. `first`, `last`, and `next` use `-1` for no link. `count` is the immediate child count; children retain insertion order. Arrays of tables have ordinary array kind and table children.
- `find(doc, parent, key)` looks up **one decoded key**, returning `-1` for a missing key or invalid/non-table parent. Dots in `key` are literal; resolve a dotted path one component at a time. Empty quoted keys are supported. Compare `kind` before reading the corresponding scalar field.
- Kinds: `Table`, `Array`, `String`, `Integer`, `Float`, `Boolean`, `OffsetDateTime`, `LocalDateTime`, `LocalDate`, `LocalTime`. Scalars use `integer`, `number`, `boolean`, or `text(doc, id)` respectively. `key(doc, id)` returns the decoded key of a table child. Array children have no meaningful key.
- Documents own every key and string/date value; the source may be modified or destroyed after parsing. `key` and `text` return borrowed views into the document, so keep it alive and do not reparse it while retaining those views. They assert that the supplied node index is in range. Reparse invalidates all previous indices and views.
- All integer forms must fit `i64`. No numeric coercion occurs. Decimal floats use Goose's correctly rounded converter; finite overflow is an error, underflow is allowed (including signed zero). Explicit signed `inf` and `nan` are supported.
- Date/time text is calendar-validated and retained as written, including arbitrary fractional precision within the scalar limit. No truncation, timezone conversion, or epoch arithmetic occurs. RFC 3339's lexical second `60` is accepted; leap-second occurrence is not checked against a historical calendar. Literal CRLF inside multiline strings is normalized to LF.

The fields supporting declaration state, hashing, arenas and index are implementation details; do not mutate the document. There is no separate immutable wrapper in this experimental API. Helper functions in the source are not stable API.

## Cost and resource limits

Parsing is linear in input size plus key-index probe/comparison work and bounded scalar conversion. Sealing skips already closed inline subtrees, so total sealing work is linear in nodes. The index uses open addressing at most 50% load with full decoded-key equality checks. It sizes storage by named entries, excluding array elements, and rehashes only indexed entries. `find` hashes O(key bytes), has expected constant probe cost and worst-case linear cost in named entries; application lookups are separate from the per-parse work budget. Deterministic hashes are **not** assumed collision-resistant: a cumulative work budget counts probes, rehash collisions, and compared key bytes, rejecting hostile workloads rather than permitting unbounded quadratic parsing.

- Input: **1 MiB**, checked before UTF-8 validation.
- Nodes: **65,536**, including the root and implicit tables.
- Logical tree depth: **64**, counting every array/table/value edge; dotted paths also have at most 64 components. Arrays of tables consume an extra edge for their element table.
- Bare scalar tokens: **128 bytes**, including numeric and date/time tokens, checked before conversion or a token copy. Strings and keys are bounded by the input cap.
- Key-index work: **16,777,216 units** per parse. Pathological inputs can exhaust this budget below the other limits.

These limits deliberately reject some otherwise valid TOML. They are fixed constants in this version. Recursion follows the checked logical depth. Arena storage is O(input bytes + nodes + index slots); rehashing temporarily copies the old index, and total storage can substantially exceed input size. The input limit is not an exact allocator budget. Reusing a document may retain previously allocated arena capacity. Out-of-memory is governed by Goose's runtime; this API does not promise recovery from allocator failure.

## Development and validation

```sh
make setup
make format check test
make conformance property security sanitize
make fuzz
make bench BENCH_ITERATIONS=10000
```

Setup requires Git, CMake 3.27+, C/C++20 compilers, Make, and libc development headers on Linux. `GOOSE_REVISION` pins the same compiler as `goose-json`; use `make GOOSE=/path/to/goose check test` with an existing compiler. Compatibility with other revisions is not guaranteed.

`make test` exercises public behavior through both Goose's in-process and native execution paths, including malformed input, source ownership, fresh-versus-reused document equivalence, recovery after every error class and both collision-budget failure phases, table declaration conflicts, Unicode, numeric boundaries, index growth, and exact resource boundaries.

`make conformance` builds the official [toml-test](https://github.com/toml-lang/toml-test) runner at `TOML_TEST_REVISION` (requires Go 1.27+, or Go's toolchain auto-download support). It runs all **208 valid and 509 invalid TOML 1.0 tests** with no skipped cases. The test-only adapter compares decoded values, not just acceptance. The suite does not prove exhaustive compliance; separate regressions cover limits and lexical leap seconds.

`make property` requires Python 3.11+ and compares 2,000 deterministically generated/mutated documents against `tomllib` on their shared subset, checking decoded types, values, signed zero, rejection, crashes and a per-input timeout. Python's arbitrary-precision integers and overflowing decimal floats are restricted to this library's numeric contract. It supplements the official suite; date/time behavior and explicit nonfinite tokens are outside this harness.

`make security` checks 272 hostile/resource documents, including an actual constructed hash-collision attack that must fail specifically through the work budget, deep/broad inline tables, dense node limits, late errors, invalid UTF-8 and arbitrary bytes. The deterministic collision generator is tied explicitly to `GOOSE_REVISION`; changing the compiler requires revalidating this test.

`make sanitize` runs the unit suite and hostile-input decoder checks with Goose debug/range checks, bounds-check elimination disabled, and GCC AddressSanitizer/UndefinedBehaviorSanitizer. It targets Linux GCC builds. CI runs conformance, property tests, security probes, sanitizers, and a bounded coverage-guided fuzz campaign in addition to the normal tests.

`make fuzz` additionally requires Clang with libFuzzer/ASan/UBSan runtimes, and the pinned official fixtures downloaded by `make conformance`. It reuses one document across fuzz inputs and checks tree links, depth, scalar child counts, key/text spans, UTF-8 output, and indexed lookups. It seeds from the 717 official TOML 1.0 fixtures plus collision/resource cases. The default campaign stops at 100,000 executions or roughly 30 seconds plus initialization/check overhead; override `FUZZ_RUNS`, `FUZZ_SECONDS`, `FUZZ_SEED`, or `FUZZ_CC` as needed. Logs, writable corpus, and failures stay in `.build/fuzz/`.

The fuzzer's C host bridges Goose's fatal `_Exit` path to `abort()` so libFuzzer can preserve the exact triggering bytes. Before each campaign it intentionally fails a Goose assertion in a separate self-test binary and verifies that the matching input artifact was written. A failed self-test or missing execution summary fails the target. Reproduce a captured input with `.build/fuzz/parser-fuzzer .build/fuzz/artifacts/crash-<hash>` and turn confirmed defects into deterministic regressions. The persistent corpus affects future mutation sequences; the numeric seed alone does not fully reproduce a campaign. This target runs Linux native code with extra checks; it is not a throughput benchmark or exhaustive TOML semantic oracle.

`make bench` uses GCC `-O2` to measure small configs, wide tables, numeric arrays, escaped/long strings, a large array followed by a named key, and deeply nested inline tables around a broad array. String decoding copies an ordinary prefix in one span and falls back to the scalar decoder after the first escape or newline. Input construction is outside the timed loop; destination reuse is inside it, and a checksum prevents dead results. These are reproducible workloads, not a machine-independent throughput or allocation claim.

For a local before/after comparison, build both parser revisions with the **same current benchmark source, pinned compiler, and GCC flags**, then run:

```sh
python3 scripts/benchmark.py --baseline /path/to/baseline-bench --candidate .build/bench
```

The harness warms both binaries, pins them to one allowed CPU on Linux, randomizes paired run order, checks workload sizes/iterations/checksums, and records nine raw samples per binary plus medians in `.build/benchmark.json`. These warm destination-reuse measurements do not establish cold latency or allocation counts. Shared-machine scheduling, CPU frequency and other load can still affect results.

For a current absolute measurement without a comparison baseline, use
`python3 scripts/benchmark.py --candidate .build/bench --output .build/benchmark.json`.
The measured snapshot, tool versions, raw samples and limitations are recorded in
[benchmark results](docs/results.md).

See [CONTRIBUTING.md](CONTRIBUTING.md), [SECURITY.md](SECURITY.md),
[platform support](docs/platforms.md), and [third-party notices](THIRD_PARTY_NOTICES.md).
Changes require focused commits, full checks and independent review.

## License

[Apache-2.0](LICENSE). Copyright 2026 goose-toml contributors.
