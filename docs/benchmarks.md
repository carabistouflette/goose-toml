# Benchmark status

Benchmark results apply to measured source and toolchains, not a library name
or the newest date in a report. The current release is alpha.6,
`e5e5644c45e78e8eb05999978bb4155ea0bbb180`.

## Alpha.6 measurements

[Alpha.6 results](alpha6-results.md) cover twelve cases: fresh parsing plus a
semantic walk, then writing an existing document. Nine rounds per series retain
all samples and show medians plus dispersion. Runtime and executable harness
hashes match the release; machine, toolchain, dependencies, output differences
and slower writer cases are explicit. The older numeric reports remain
historical. See the [identity audit](benchmark-currentness.json).

Source-editor latency and memory improvements are **not claimed for alpha.6**.
Its earlier experiments remain historical. A separate source-editor benchmark
rerun would not support a claim made by this guide, so it is outside this audit.
Inline replacement/insertion reports are correctness records, with no speed claim.

## Reproduce a new comparison

Install the [pinned tools and dependencies](../bench/compare/README.md), freeze
the source, and coordinate a quiet host window. From the repository root:

```sh
python3 scripts/compare.py --cpu 3 --build-only --corpus extended
python3 scripts/compare.py --cpu 3 --corpus extended --mode full --no-build --iterations 100000 --rounds 9 --seed 20261104 --timezone UTC --output .build/compare/announcement-full.json
python3 scripts/compare.py --cpu 3 --corpus extended --mode write --no-build --iterations 100000 --rounds 9 --seed 20261104 --timezone UTC --output .build/compare/announcement-write.json
```

Choose a CPU allowed on your machine. Affinity does not isolate a shared host.
Use the same compiler, dependencies and flags for each repeated comparison.
Each case/language gets one warmup at one tenth its measured iteration count
(at least one), then nine shuffled rounds. Larger cases use fewer iterations
through fixed per-case divisors. Raw samples and distributions belong with every
table; medians alone do not establish statistical significance.

Full parsing includes a fresh owned document, root count, full semantic walk and
cleanup. Goose walks a flat arena; other implementations walk trees or maps.
Writing excludes the initial parse but includes fresh output, consumption and
cleanup. Default formatting, output sizes, validation and allocator/GC costs
differ; this is not equal-byte or allocation-normalized work. Untimed preflight
checks decoded values, types, float bits and datetime components against Python
`tomllib`, and independently parses each writer's output. UTC is fixed for the
datetime corpus. See the [complete protocol](../bench/compare/README.md).

## Historical records

These pages retain original raw artifacts, machines, tool versions, commands,
slower results and limitations. To reproduce a historical table, check out its
named immutable source and use its recorded harness/toolchain. Running those
commands on alpha.6 produces a new experiment, not a reproduction.

| Record | Measured scope | Status against alpha.6 |
| --- | --- | --- |
| [Parser snapshot](results.md) | Warm destination reuse, eight cases | Parser implementation differs |
| [Original comparison](comparison-results.md) | Full/root parse and write, eight cases | Core and adapters differ |
| [Expanded comparison](extended-results.md) | Full parse/write, twelve cases; writer profile/change | Core differs; executable comparison harness and dependency pins match |
| [Source profile/history](../source/docs/history.md) | Four-case source operations and legacy consolidation | Editor differs; includes an 8.5% small-removal regression |
| [Document reuse](../source/tests/results/document-reuse/README.md) | Default/legacy, wrapper calls, storage instrumentation | Editor differs; mixed tiny/comment results, retained 9.3% outlier and fixture-specific region counts |
| [Atomic batches](../source/tests/results/atomic-batches/README.md) | Batch versus sequential complete operations | Editor differs; retains 12.5% slower one-edit control and initial comparison |

The expanded historical harness has a changed README in this documentation
revision; its executable sources and dependency locks are unchanged. The fresh
build fingerprints that documentation change too. No broad runtime bridge
is valid: parser index/error handling and writer integer/float paths changed.
