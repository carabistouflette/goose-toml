# Development and validation

Use the compiler in `GOOSE_REVISION`. Historical execution counts are not
coverage guarantees. Check [benchmark status](benchmarks.md) before quoting
timing results.

## Commands

```sh
make setup
make format check test
make conformance property scalar writer-scalar security sanitize
make fuzz
make bench BENCH_ITERATIONS=10000
```

Setup requires Git, CMake 3.27+, C/C++20 compilers, Make, and libc development headers on Linux. `GOOSE_REVISION` pins the supported compiler; use `make GOOSE=/path/to/goose check test` with an existing compiler. Compatibility with other revisions is not guaranteed.

`make test` exercises public behavior through both Goose's in-process and native execution paths, including 2,000 model-based editor steps, serializer round trips and 2,000 deterministic raw float bit patterns, version-specific syntax, malformed input, source ownership, fresh-versus-reused document equivalence, recovery after every error class and both collision-budget failure phases, table declaration conflicts, Unicode, numeric boundaries, index growth, and exact resource boundaries.

`make conformance` builds the official [toml-test](https://github.com/toml-lang/toml-test) runner at `TOML_TEST_REVISION` (requires Go 1.27+, or Go's toolchain auto-download support). It runs all **208 valid, 509 invalid and 208 encoder cases for TOML 1.0**, and **218 valid, 502 invalid and 218 encoder cases for TOML 1.1**, with no skipped cases. Test-only adapters compare decoded values and validate constructed documents through the independent official encoder oracle, not just acceptance. The suite does not prove exhaustive compliance; separate regressions cover limits and lexical leap seconds.

`make property` requires Python 3.11+ and compares 2,000 deterministically generated/mutated documents against `tomllib` on their shared subset, checking decoded types, values, signed zero, rejection, crashes and a per-input timeout. Python's arbitrary-precision integers and overflowing decimal floats are restricted to this library's numeric contract. It supplements the official suite; date/time behavior and explicit nonfinite tokens are outside this Python harness. Separate writer tests cover these kinds and 2,000 model-based editor steps check an independent fixed-slot/array model.

`make scalar` compares 356,572 deterministic numeric/boolean cases against Python's `tomllib`: all length-0..5 tokens over a representative 12-character numeric alphabet, radix and i64 boundaries, tokens around the 128-byte cap, rounding midpoints, extreme exponents and signed zero. A batched public-API adapter reuses the destination across accepted and rejected documents; unexpected diagnostics, crashes, malformed frames and missing/extra responses fail separately from parse errors. Finite numeric results are compared as raw IEEE-754 bytes, including signed zero, without using Goose's float formatter; NaNs allow either sign and any nonzero NaN fraction. The same campaign runs under ASan/UBSan in `make sanitize`.

`make writer-scalar` constructs binary64 values directly from raw bits and independently decodes serialized TOML with Python `tomllib`. It checks **169,854 cases**: 100,000 seeded raw patterns plus 69,854 biased exponent, mantissa, subnormal, decimal-fraction and transition cases. Float kind, finite bits, signed zero and infinities must match exactly; NaNs follow the semantic contract. The adapter never invokes Goose's TOML or decimal parser. Framing, diagnostics, crashes and timeouts fail separately. It also checks 100,337 independent signed-integer cases. Both campaigns run under ASan/UBSan and Python `-O` in `make sanitize`.

`make security` checks 274 hostile/resource documents and nine encoder-protocol regression cases, including constructed bucket collisions and full 64-bit hash collisions with long shared key prefixes. These must fail specifically through probe or compared-key-byte work limits. It also checks deep/broad inline tables, dense node limits, late errors, invalid UTF-8 and arbitrary bytes. The deterministic collision generator is tied explicitly to `GOOSE_REVISION`; changing the compiler requires revalidating this test.

`make sanitize` runs the unit suite and hostile-input decoder checks with Goose debug/range checks, bounds-check elimination disabled, and GCC AddressSanitizer/UndefinedBehaviorSanitizer. It targets Linux GCC builds. CI runs conformance, property tests, scalar grammar/rounding checks, security probes, sanitizers, and a bounded coverage-guided fuzz campaign in addition to the normal tests.

`make fuzz` additionally requires Clang with libFuzzer/ASan/UBSan runtimes, and the pinned official fixtures downloaded by `make conformance`. It reuses document arenas across fuzz inputs and both spec versions, serializes successful parses, reparses strict TOML 1.0, and checks semantic equality plus tree links, depth, scalar child counts, key/text spans, UTF-8 output, and index integrity. Index-cluster and per-node hash checks scan the entire
index; a bounded sample additionally exercises public lookups, avoiding quadratic
harness work on collision-heavy seeds. Each complete two-version case has a
15-second deadline under coverage and sanitizers; this is a harness timeout,
not a parser latency guarantee. It seeds from the union of both official manifests (785 fixture paths, content-deduplicated) plus collision/resource cases. The default campaign stops at 100,000 executions or roughly 30 seconds plus initialization/check overhead; override `FUZZ_RUNS`, `FUZZ_SECONDS`, `FUZZ_SEED`, or `FUZZ_CC` as needed. Logs, writable corpus, and failures stay in `.build/fuzz/`.

The fuzzer's C host bridges Goose's fatal `_Exit` path to `abort()` so libFuzzer can preserve the exact triggering bytes. Before each campaign it intentionally fails a Goose assertion in a separate self-test binary and verifies that the matching input artifact was written. A failed self-test or missing execution summary fails the target. Reproduce a captured input with `.build/fuzz/parser-fuzzer .build/fuzz/artifacts/crash-<hash>` and turn confirmed defects into deterministic regressions. The persistent corpus affects future mutation sequences; the numeric seed alone does not fully reproduce a campaign. This target runs Linux native code with extra checks; it is not a throughput benchmark or exhaustive TOML semantic oracle.

`make bench` uses GCC `-O2` to measure small configs, wide tables, numeric arrays, escaped/long strings, a large array followed by a named key, and deeply nested inline tables around a broad array. String decoding uses the standard library byte-set search for long ordinary prefixes, copies the prefix in one span and falls back to the scalar decoder after the first escape or newline. Input construction is outside the timed loop; destination reuse is inside it, and a checksum prevents dead results. These are reproducible workloads, not a machine-independent throughput or allocation claim.

For a local before/after comparison, build both parser revisions with the **same current benchmark source, pinned compiler, and GCC flags**, then run:

```sh
python3 scripts/benchmark.py --baseline /path/to/baseline-bench --candidate .build/bench
```

The harness warms both binaries, pins them to one allowed CPU on Linux, randomizes paired run order, checks workload sizes/iterations/checksums, and records nine raw samples per binary plus medians in `.build/benchmark.json`. These warm destination-reuse measurements do not establish cold latency or allocation counts. Shared-machine scheduling, CPU frequency and other load can still affect results.

For a current absolute measurement without a comparison baseline, use
`python3 scripts/benchmark.py --candidate .build/bench --output .build/benchmark.json`.
The [historical parser report](results.md) illustrates the recorded fields;
a new run must retain its own source identity, raw samples and limitations.

Historical [expanded parsing and writing results](extended-results.md) include twelve workloads, matched writer profiles, raw nine-round reports and limitations. The [initial eight-workload comparison](comparison-results.md) remains available with its original provenance.

For pinned Rust, Go and C++ feature coverage, see [the feature matrix](comparison-features.md). Reproduce fresh owned-document parsing comparisons with [the comparison harness](../bench/compare/README.md). Language-specific struct binding and source-format preservation remain outside the common semantic workflow.

See [CONTRIBUTING.md](../CONTRIBUTING.md), [SECURITY.md](../SECURITY.md),
[platform support](platforms.md), and [third-party notices](../THIRD_PARTY_NOTICES.md).
Changes require focused commits, full checks and independent review.


## Source editor

From the repository root, after setup and fetching conformance fixtures:

```sh
make -C source format check test property conformance
make -C source sanitize SANITIZER_CC=gcc
make -C source sanitize SANITIZER_CC=clang
make -C source fuzz
```

The source module has separate byte-preservation, aliasing, batch, inline and
legacy-profile tests. Its benchmark smoke target checks execution, with no
performance threshold. Historical execution counts and timing series are in
[source history](../source/docs/history.md). Coordinate shared-machine builds
and measurements with other users; CPU affinity alone does not isolate a host.
