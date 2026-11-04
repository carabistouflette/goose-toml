# Expanded parsing and writing measurements

Measured code and benchmark source: [`7f12af5c7d26d077b531383589949b5c976f5a68`](https://github.com/carabistouflette/goose-toml/commit/7f12af5c7d26d077b531383589949b5c976f5a68). Built from an isolated checkout of the tracked source. The reported untracked `.toolchain` entry is a symlink to external pinned development tools, not modified library source.

Twelve inputs include the original eight workloads, original app/server and project configurations, a schedule covering all four TOML datetime kinds, and finite floats from subnormal values through ±1e300. The default benchmark corpus remains the original eight. [Methodology and setup](../bench/compare/README.md).

Pinned Rust toml 1.2.0+spec-1.1.0, Go BurntSushi/toml v1.6.0, and C++ toml++ v3.4.0. Nine shuffled paired rounds, CPU1 affinity on a shared workstation; no exclusive isolation or universal speed claim. Per-input medians are descriptive, not significance tests.

## Fresh parse plus semantic walk

[Raw nine-round report](../bench/results/2026-11-04-extended-full.json). Median microseconds per operation, lower is better.

| Workload | Goose | Rust | Go | C++ |
| --- | ---: | ---: | ---: | ---: |
| small-config | 0.553 | 2.393 | 10.043 | 2.515 |
| wide-table | 177.703 | 1168.984 | 2649.313 | 884.943 |
| float-array | 69.426 | 439.046 | 589.860 | 655.779 |
| escaped-strings | 20.132 | 94.982 | 279.836 | 129.080 |
| integer-array | 91.166 | 384.921 | 493.351 | 323.561 |
| long-literal | 141.454 | 376.579 | 4997.399 | 7017.031 |
| array-then-key | 3889.322 | 22236.996 | 25794.526 | 7952.186 |
| nested-inline-array | 4492.339 | 23151.024 | 28694.987 | 7725.349 |
| app-server | 11.358 | 47.392 | 165.132 | 70.593 |
| build-project | 13.574 | 56.465 | 205.272 | 78.626 |
| datetime-heavy | 149.920 | 719.390 | 1706.821 | 749.724 |
| finite-float-range | 84.700 | 104.942 | 199.166 | 259.830 |

Goose has the lowest observed median in 12/12 cases in this mode.

## Existing-document writing

[Raw nine-round report](../bench/results/2026-11-04-extended-write.json). Median microseconds per operation, lower is better.

| Workload | Goose | Rust | Go | C++ |
| --- | ---: | ---: | ---: | ---: |
| small-config | 0.398 | 0.576 | 6.297 | 0.764 |
| wide-table | 92.352 | 81.306 | 1352.665 | 123.203 |
| float-array | 161.359 | 146.702 | 357.053 | 545.801 |
| escaped-strings | 13.794 | 14.619 | 125.774 | 18.563 |
| integer-array | 44.681 | 36.197 | 300.746 | 65.617 |
| long-literal | 148.098 | 456.125 | 453.193 | 1126.977 |
| array-then-key | 2851.270 | 1902.639 | 17132.302 | 4046.683 |
| nested-inline-array | 2795.812 | 1858.029 | 17482.517 | 4121.682 |
| app-server | 8.004 | 10.630 | 91.295 | 16.576 |
| build-project | 8.696 | 11.965 | 112.032 | 15.853 |
| datetime-heavy | 74.878 | 527.401 | 1452.780 | 165.721 |
| finite-float-range | 259.298 | 35.285 | 88.846 | 214.384 |

Goose has the lowest observed median in 6/12 cases in this mode.

## Scope and semantic checks

Existing correctness/fuzz and consumer-build jobs with unrestricted affinity may have overlapped early samples. They were allowed to finish uninterrupted. All samples remain retained; coordination did not establish exclusive isolation.

Every parser receives identical bytes. Preflight compares actual values and kinds against Python tomllib, exact binary64 bits including negative zero, and explicit datetime wall components/offsets. Full-visit checksums consume values; the wide-float schema avoids float-to-integer overflow. Datetime inputs use at most six fractional digits so Python can independently represent the tested precision. This does not establish arbitrary-precision datetime equivalence.

Writer timing excludes parsing and includes fresh owned output creation/consumption/cleanup. Actual serializer output is independently reparsed before timing. Default quoting, layout, wrapping, float spellings, output byte counts, validation and copying differ between libraries; those costs stay included. Output sizes and hashes accompany each report. No equal-byte formatting or allocation-normalized claim is made.

Extended timings explicitly set **TZ=UTC for all four processes**. Separate UTC/Europe-Paris diagnostics are retained: parsing preserves values in both environments, but the pinned Go default writer shifts local wall values under Europe/Paris. That discrepancy is reported, not counted as a successful equivalent writer run. Original timings inherit the host timezone unless overridden.

## Writer profile and matched change

The original float-array profile spent about 75% of whole-process instructions in the runtime formatter and its digit/big-integer setup. The retained change uses the pinned standard library public formatter only within a proven fast magnitude window, retaining the original formatter outside it and explicit nonfinite/signed-zero handling. [Profile summary](../bench/results/2026-11-04-writer-profile.json).

[Matched before/after raw samples](../bench/results/2026-11-04-writer-paired.json) use the same final adapter source, pinned Goose compiler and GCC -O2 flags; only writer.goose changes. Baseline writer is from e8a605b. Nine randomized pairs per input, with independent semantic output checks. Different legal spellings can change output lengths.

| Float workload | Baseline µs | Candidate µs | Observed speedup |
| --- | ---: | ---: | ---: |
| float-array | 165.208 | 155.025 | 1.066× |
| finite-float-range | 261.684 | 245.301 | 1.067× |

Small changes elsewhere remain subject to shared-host noise. This optimization does not establish that the writer is faster for all inputs.

The alpha also includes later consumer-overload hardening, including direct pinned-runtime formatting and a narrower fast-path window. The tables above remain measurements of the stated 7f12af5 snapshot, not fresh measurements of those later changes.

## Reproduce

```sh
python3 scripts/compare.py --cpu 1 --corpus extended --mode full --iterations 100000 --rounds 9 --output .build/compare/extended-full.json
python3 scripts/compare.py --cpu 1 --corpus extended --mode write --no-build --iterations 100000 --rounds 9 --output .build/compare/extended-write.json
make writer-scalar
```

Additional compiler/tool dependencies and the explicit timezone policy are documented in the methodology. The earlier [eight-input reports](comparison-results.md) remain historical measurements of their stated source.
