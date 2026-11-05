# Parsing and writing comparison

**Historical measurements.** These implementation hashes differ from alpha.6.
Keep these samples tied to their measured revision; see [benchmark status](benchmarks.md)
for currentness and [methodology](../bench/compare/README.md) for measurement scope.

Measured source: [`65022d8c1db0181c26a3dcc6bbde569c71d65be3`](https://github.com/carabistouflette/goose-toml/commit/65022d8c1db0181c26a3dcc6bbde569c71d65be3). All three reports were built from this clean commit.

Pinned comparators: Rust `toml` 1.2.0+spec-1.1.0, Go BurntSushi/toml v1.6.0, and C++ toml++ v3.4.0. See [feature differences](comparison-features.md) and [complete methodology and reproduction](../bench/compare/README.md).

Measurements use nine shuffled paired rounds on CPU1 of a shared Linux x86-64 workstation. Affinity is not isolation. Raw samples, dispersion, input hashes, binary/source hashes, effective Rust compiler options, tool versions and dependency provenance accompany each report. No universal or machine-independent winner follows from this corpus.

## Fresh parse plus semantic walk

[Raw report](../bench/results/2026-11-04-comparison-full.json). Values below are median microseconds per operation; lower is better.

| Workload | Goose | Rust | Go | C++ |
| --- | ---: | ---: | ---: | ---: |
| small-config | 0.569 | 2.366 | 10.281 | 2.514 |
| wide-table | 183.137 | 1182.927 | 2697.798 | 905.230 |
| float-array | 71.375 | 443.632 | 586.298 | 664.564 |
| escaped-strings | 19.718 | 97.757 | 289.946 | 129.890 |
| integer-array | 91.534 | 387.842 | 507.963 | 324.111 |
| long-literal | 148.351 | 379.123 | 5063.644 | 7151.271 |
| array-then-key | 3865.168 | 22101.822 | 27180.051 | 7924.165 |
| nested-inline-array | 4514.270 | 22324.390 | 28910.343 | 7819.872 |

Goose has the lowest observed median in 8 of 8 workloads in this mode. This count is descriptive, not a statistical significance test.

## Fresh parse plus root count

[Raw report](../bench/results/2026-11-04-comparison-root.json). Values below are median microseconds per operation; lower is better.

| Workload | Goose | Rust | Go | C++ |
| --- | ---: | ---: | ---: | ---: |
| small-config | 0.502 | 2.270 | 9.754 | 2.383 |
| wide-table | 176.963 | 1182.617 | 2629.686 | 881.008 |
| float-array | 66.130 | 430.621 | 583.577 | 639.579 |
| escaped-strings | 19.543 | 94.268 | 276.732 | 129.842 |
| integer-array | 85.565 | 373.375 | 498.031 | 314.330 |
| long-literal | 144.834 | 376.099 | 4912.222 | 7096.193 |
| array-then-key | 3495.555 | 21427.931 | 26805.946 | 7233.228 |
| nested-inline-array | 4110.689 | 22582.838 | 28957.467 | 7219.398 |

Goose has the lowest observed median in 8 of 8 workloads in this mode. This count is descriptive, not a statistical significance test.

## Serialize an existing document

[Raw report](../bench/results/2026-11-04-comparison-write.json). Values below are median microseconds per operation; lower is better.

| Workload | Goose | Rust | Go | C++ |
| --- | ---: | ---: | ---: | ---: |
| small-config | 0.392 | 0.557 | 6.146 | 0.743 |
| wide-table | 89.116 | 78.567 | 1320.375 | 122.815 |
| float-array | 168.162 | 146.171 | 353.408 | 543.446 |
| escaped-strings | 13.337 | 14.568 | 121.204 | 18.199 |
| integer-array | 44.694 | 35.424 | 290.625 | 64.030 |
| long-literal | 148.494 | 441.280 | 446.260 | 1099.868 |
| array-then-key | 2847.865 | 1815.953 | 16800.111 | 3943.698 |
| nested-inline-array | 2904.040 | 1837.427 | 17465.967 | 4060.680 |

Goose has the lowest observed median in 3 of 8 workloads in this mode. This count is descriptive, not a statistical significance test.

Parsing occurs outside the writer timer; fresh output construction, consumption and cleanup are timed. Each actual output is independently reparsed with Python `tomllib`. Formatting and validation work differ: Goose quotes keys and uses inline tables, while competitors choose their default table layout, wrapping and ordering. Output byte counts and hashes are recorded per language. These are default public API timings, not equal-byte formatting comparisons.

## Reproduction

Run `make setup` and install the additional pinned benchmark dependencies as described in the methodology. Then:

```sh
git checkout --detach 65022d8c1db0181c26a3dcc6bbde569c71d65be3
python3 scripts/compare.py --cpu 1 --iterations 100000 --rounds 9 --mode full --output .build/compare/final-full.json
python3 scripts/compare.py --cpu 1 --no-build --iterations 100000 --rounds 9 --mode root --output .build/compare/final-root.json
python3 scripts/compare.py --cpu 1 --no-build --iterations 100000 --rounds 9 --mode write --output .build/compare/final-write.json
```

The same eight inputs are used in every language without lowering their native limits. All accept the original depth-60 case. The corpus contains no datetimes and only exactly representable `1.25` floats: it makes no datetime, general float-conversion, allocation-count, peak-memory or cold-start performance claim. Full mode includes a flat arena visit in Goose and tree/map visits elsewhere; root mode is reported separately. GC and allocator behavior remain native to each language.

## Feature and validation evidence

The shared semantic workflow is implemented: strict TOML 1.0 parsing, optional TOML 1.1, document construction/mutation and complete semantic TOML 1.0 writing. At this measured snapshot, automatic host struct binding and comment/format
preservation are not provided by the compared semantic API; fixed resource limits can reject valid larger documents. See [editor contracts and limits](document.md).

Both official suites pass at the pinned TOML_TEST_REVISION: 1.0 has 208 valid, 509 invalid and 208 encoder cases; 1.1 has 218 valid, 502 invalid and 218 encoder cases. Local checks also pass 2,000 differential property inputs, 2,000 model-based editor steps, 2,000 float-bit writer roundtrips, 356,572 scalar oracle cases, 274 hostile/resource cases and nine encoder protocol cases. GCC ASan/UBSan and a 3,500-execution Clang/libFuzzer campaign covering both versions and write/reparse semantics pass. Independent reviewers checked compatibility, bounds, borrowed lifetimes, output caps and benchmark fairness; concrete findings were fixed before freezing. These checks provide evidence, not exhaustive correctness or a security guarantee.
