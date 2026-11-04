# Pinned TOML comparisons

These original Apache-2.0 adapters compare fresh, owned DOM parsing and writing
of the same eight byte sequences from `bench/parse.goose`. They are a measurement tool, not
a portable ranking. Generated inputs, binaries, raw samples and reports stay in
the ignored `.build/compare/` directory. Dependency implementations stay outside
the source tree; licenses and source URLs are in `dependencies.json` and the
generated build manifest, including Cargo's transitive dependencies.

Install Rust/Cargo, Go, GCC/G++, Python 3.11+, and the pinned Goose toolchain with
the repository setup script. Prepare the ignored C++ dependency checkout:

```sh
git clone https://github.com/marzer/tomlplusplus.git .toolchain/tomlplusplus
git -C .toolchain/tomlplusplus checkout --detach 30172438cee64926dc41fdd9c11fb3ba5b2ba9de
```

Build and run from the library root:

```sh
python3 scripts/compare.py --cpu 1 --iterations 100000 --rounds 9
```

Choose an allowed CPU; omitting `--cpu` selects the minimum allowed CPU and warns
that affinity does not reserve a shared machine's core. Coordinate with other
host users before measuring. A smoke run uses `--iterations 1000 --rounds 1`;
its short samples are useful for checking the protocol, not comparing speed.
The base iteration count is divided by the same per-workload factors as
`bench/parse.goose`; every runner gets exactly the same resulting count.

Useful separate steps and the lighter root-count mode:

```sh
python3 scripts/compare.py --cpu 1 --build-only
python3 scripts/compare.py --cpu 1 --no-build --iterations 100000 --rounds 9
python3 scripts/compare.py --cpu 1 --no-build --mode root --output .build/compare/root-report.json
python3 scripts/compare.py --cpu 1 --no-build --goose-reuse --output .build/compare/with-reuse-report.json
python3 scripts/compare.py --cpu 1 --no-build --mode write --output .build/compare/write-report.json
python3 scripts/compare.py --cpu 1 --generate-only
```

`--no-build` requires source and binary hashes to match `.build/compare/build.json`.
Changing library sources requires a new build. The harness rejects changed inputs,
different counts, malformed runner output, root counts or structural checksums.
Each runner accepts `INPUT ITERATIONS full|root|decode|write|write-decode`. It reads the input once,
computes an FNV64 byte fingerprint before timing, and returns one JSON object.
The orchestrator independently verifies the input's SHA-256 before and after
each process. `decode` emits the actual decoded JSON tree; every value and type
must match Python's independent `tomllib` parse before measurement begins.

Default `full` timing includes parse, immediate root-count consumption, a full
semantic node visit and scope cleanup. Its twelve additive checksum fields are
node/table/array/string/integer/float/bool counts, UTF-8 key and string byte
lengths, integer sum, sum of floats multiplied by 1000 and truncated, and true
count. String contents are checked in the independent preflight rather than
hashed inside the timing. Only exactly representable `1.25` floats occur in this
corpus. The checksum is a workload guard, not a collision-resistant tree hash.
Goose visits its flat node buffer while competitors visit their tree/map DOMs.
`root` excludes the structural visit; its results must be labeled separately.
Optional `--goose-reuse` measures a reused destination through the same checksum
path and records it separately; its medians are excluded from the fresh-DOM
comparison table. The equivalent Goose runner modes are `full-reuse` and
`root-reuse`.

Every iteration creates a fresh semantic document. Goose uses scope-managed
data stacks, whose backing pages may stay warm; Rust and C++ use standard owned
containers and allocators. Go decodes into a fresh `map[string]any` with standard
optimization and enabled default GC. Collections during the loop are included;
collection of garbage remaining after the loop is not forced. No language is
handicapped with extra allocator clears, page trimming or forced collection.
This benchmark does not measure normalized allocations or peak memory.

`write` is a separate measurement: each runner parses the identical input once
outside the timer, then serializes the DOM to a fresh owned output every
iteration. It uses Goose `toml::serialize`, Rust `toml::to_string`, Go
`toml.Marshal`, and C++ `toml::toml_formatter` through a fresh
`std::ostringstream` followed by `str()`, all with default formatting options.
Fresh output creation, length/first/last-byte consumption, and scope cleanup
are timed; parsing and independent output validation are excluded. Go keeps
normal GC enabled and does not force collection after each output. Writer mode
does not support `--goose-reuse`.

`write-decode` prints the exact serialized TOML without adding a newline. Before
writer timing, Python `tomllib` reparses each serializer's output and requires
all decoded values and types to match the original input. The report records
each language's serialized byte count, SHA-256 and first/last byte per workload.
The writer JSON response strictly contains `iterations`, `input_bytes`,
`input_fnv64`, `elapsed_ns`, `serialized_bytes`, `output_bytes_total`, and
`output_edge_total`; its counters must match that independently checked output.
Each iteration consumes output length plus the first and last bytes through an
optimization barrier (or a non-inlined Go call and `runtime.KeepAlive`). The
full output is not hashed or reparsed inside the timed loop.

Writing and parsing use separate timing keys (`median_ns_per_write` versus
`median_ns_per_parse`, with corresponding sample/distribution keys). Default
serializers choose different whitespace, ordering, quoting, table headers,
inline syntax and wrapping, so they emit different byte counts. Their public
APIs also perform different validation, scratch allocation and copying. All
those costs stay included. These default-API timings establish neither equal
formatting work nor a universal serializer winner.

Rust calls `str::parse::<toml::Table>()` with default features in Cargo's standard
release profile (`opt-level=3`, no LTO). Explicit environment overrides enforce
release settings, empty extra flags, disabled incremental compilation and empty
compiler wrappers, including when user Cargo config requests native CPU flags
or LTO. An explicit rustc host target overrides Cargo's configured build target.
The adapter package is rebuilt with verbose Cargo output each time, and the
effective rustc command is checked for the expected optimization, codegen-unit,
debug, LTO, target, linker and incremental settings. Sanitized effective settings
are recorded in the report; the full local command log remains in ignored
`.build/compare/cargo-build.log`. Cargo's requirement `=1.2.0` fixes SemVer;
the committed lockfile, official archive checksum and metadata check enforce
the complete `1.2.0+spec-1.1.0` version because Cargo ignores build metadata in
version requirements. Go uses BurntSushi/toml `v1.6.0` and locked module sums.
C++ uses `toml::parse(std::string_view)` from toml++ `3.4.0` at the full commit
above, compiled with GCC `-O2`, matching Goose's GCC `-O2`. Default parser caches,
table/index strategies, recursion limits and datetime precision stay enabled.
The shared corpus uses TOML 1.0 constructs and no datetimes; it establishes no
datetime throughput or precision claim. Rust supports TOML 1.1, while Goose's
runner uses the library's strict default TOML 1.0 API.

Before timing, all parsers attempt the original depth-60 nested inline workload.
If a parser reports its native depth/recursion limit, the original bytes and
error remain in the manifest and every parser receives an explicitly named
depth-30 replacement with the same 60,000-element array. Other errors stop the
run. Limits are never disabled, and workloads are never silently omitted.

Warm-up processes precede nine rounds by default. In each round the workload
order and each workload's runner order are shuffled with a recorded seed.
Every sample is a new process; input loading, fingerprinting, output formatting
and process startup are outside its internal timer. The report retains sample
order, CPU affinity, counters, raw nanoseconds and medians, plus compiler versions,
dependency versions/licenses/checksums, build settings and source/binary hashes.
It contains no private absolute paths. Short samples, process initialization,
shared-host interference and frequency drift remain material limitations.
