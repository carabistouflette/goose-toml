# Terminal Document reuse: experimental results

**Decision: retain as an unreleased candidate for review; do not advance any
published release or consumer pin.** Correctness and ownership checks passed.
The fixture uses three fewer runtime data-stack regions, and selected wide
workloads show repeatable reductions in measured time. These observations do
not establish a general latency improvement or prove the absence of regressions.

The runtime change only passes the existing private Document into terminal
`parse_into` after every source-node read and copy has finished. It preserves
source/legacy policy, public signatures, fresh per-call state, parser work
limits, error precedence, output clearing and ownership. Lookup, subtree bitmap,
quoting and fragment parsing are unchanged.

## Identities

- Published runtime baseline: `de7dfe092f6d72811417355044e5d024d5600613`.
- Initial fixture-bearing baseline: `3f111333d685a9d2aa0c1a71d1a7e001e9e0ea14`.
- Refined fixture-bearing baseline: `ff13455e3e969f5fa1e3bd3362b1f98cac64a581`;
  its engine is byte-identical to the published baseline.
- Reviewed/validated engine checkpoint: `a79cf60ff6ba86dd887dd5749f5b312ca0ef48b4`.
- Refined measurement candidate: `b1c31f7f8af62b2da8945ceef189d7daa7cbc813`;
  engine and oracle blobs match the validated checkpoint.
- Candidate engine SHA-256:
  `1fa20fcb1bb3c7ad1751788ae34d6c91dd348397e8871283da6c687c222b59c1`.
- Public companion baseline: `ae32f13d69b69c9604a44d7acd71d2f966daef35`.
  Its candidate export intentionally replaces **only** the canonical editor;
  the released vendor manifest is retained and therefore intentionally differs
  from that experimental editor. It is not a verified released vendor snapshot.

The separate alias gate and complete source/binary identities are retained in
[validation.json](validation.json) and [adapter-alias-gate.json](adapter-alias-gate.json).
The baseline fixture-only precision commit is retained in experiment history
so exact baseline objects remain available for reproduction.

## Correctness and ownership

Two independent code reviews found no terminal lifetime/alias/precedence blocker.
All final parsing paths consume old offsets/node metadata before the reset;
default missing removal retains its fast owned-copy path, while legacy missing
removal still reparses. Reader/work state and Document logical lengths reset.

Validation passed JIT, optimized and debug direct tests; 2,405 default model
cases and 533 legacy byte/diagnostic cases per model variant; 717 TOML 1.0 and
720 TOML 1.1 source-index fixtures; GCC/Clang ASan/UBSan; and 16,872 Clang fuzz
executions in 31 seconds with the assertion-artifact self-test. New tests cover
large value growth, shrinkage including named-key index reset, scattered
subtrees, borrowed path/value/source storage and retained final-parse errors.

A fresh 5,134-call differential against frozen clean `cedb2c3` compared exact
status/output/error bytes and failure emptiness, with Python `tomllib` checking
successful outputs. Candidate HEAD, clean state, source/Git blobs and binary
hashes were checked before/after. The isolated released-adapter overlay passed
all eight unchanged direct execution modes and both sanitizer toolchains,
including 234 property calls each. The different compiler binary used for that
adapter correctness gate is disclosed in its report; paired timing binaries
were built with one identical compiler binary instead.

**Hosted x86/ARM checks have not run for this unreleased experiment.** Local
checks are not a substitute for exact-head hosted validation before adoption.

## Measurement protocol and limitations

Linux x86-64, Intel Core Ultra 7 258V, CPU affinity 6, pinned Goose `eadca409`,
GCC 16.2.1 and `-O2`. All runs use a shared host with **no exclusive isolation**.
Early correctness work on CPUs 2/3/5 overlapped portions of initial measurements;
those observations are retained. Later rounds also have no exclusivity claim.

Every source campaign contains nine shuffled rounds with alternating per-case
runner order. Baseline/candidate fixture, parser/writer, compiler and executable
identities are checked. Ratios below are ratios of medians, not confidence
intervals. A separately started confirmation uses the same frozen configuration.
The unchanged-binary control runs the baseline executable under both labels.
It shows host/run variation; it is not a statistical uncertainty bound.

The first calibration was too close to the 10 ms minimum; six tiny cases hit
the 10,000-call cap, and some measured batches fell below the minimum. Those
cases are explicitly ineligible for timing claims. All original raw samples
remain in `reuse-*.json` without being silently removed.

The refined fixture raises the count bound to 100,000 in **both** snapshots,
with identical fixture hashes. Calibration targets 30 ms and retains the
10 ms minimum. All 36 refined cases meet that minimum in the comparison and
confirmation. The driver always preflights exact bytes, so these are calls
after preflight, even with zero additional warmups; true cold use was not measured.
The driver checks exact output before/after timing, and only status, length and
an endpoint checksum inside it. That checksum alone cannot detect middle-byte
corruption in a particular timed iteration.

The unchanged six-case public companion harness bounds each process at 10,000
calls. Its refined protocol aggregates enough fixed-count process batches to
meet the same target, retaining every component duration/checksum. Construction
and process startup are outside each runner's internal timer; first library use
within each batch is included and amortized. Both original single-process
series and refined aggregated series are retained. A `no_timings_run` field in
the original producer handoff means the producer had not executed those binaries
at handoff time, not that these later measurements did not execute them.

Sources, scripts, compiler, binaries, configuration and batch counts are recorded
in the JSON files. Local workspace prefixes are normalized to `$WORKSPACE` and
JSON layout is compacted; samples/values are unchanged. Each file retains the
SHA-256 of its original local artifact. Generated C, executables, toolchains and
raw logs remain in ignored `.build/`, outside this results directory.

[Interactive comparison](comparison.html) shows all refined fixture groups,
public calls and the original default benchmark, including control/outlier data.

## Refined source fixtures: all observations

Target `-1` means missing. Negative percentages mean less measured elapsed time.
The unchanged-binary control can be noticeably nonzero. Individual movements
above 5%, in either direction, must be read alongside the confirmation and
control; they are not automatically attributable to the code change.

### source profile

| Operation / shape | First | Confirmation | Unchanged control |
| --- | ---: | ---: | ---: |
| remove, 0 comment bytes, 1 keys, target 0 | +0.1% | +1.5% | +3.3% |
| remove, 0 comment bytes, 8 keys, target 0 | +2.0% | -11.5% | -4.4% |
| remove, 0 comment bytes, 8 keys, target 7 | -3.2% | -1.7% | -3.9% |
| remove, 0 comment bytes, 32 keys, target 0 | +3.2% | -1.4% | -2.1% |
| remove, 0 comment bytes, 32 keys, target 31 | +0.2% | +1.0% | +1.6% |
| set, 65536 comment bytes, 1 keys, target 0 | -0.7% | +0.2% | +5.6% |
| remove, 65536 comment bytes, 1 keys, target 0 | -5.1% | +0.1% | -3.7% |
| set, 1000000 comment bytes, 1 keys, target 0 | +2.9% | +0.5% | +3.2% |
| remove, 1000000 comment bytes, 1 keys, target 0 | +0.7% | -0.1% | +0.8% |
| set, 0 comment bytes, 10000 keys, target 0 | -8.9% | -14.4% | -0.7% |
| remove, 0 comment bytes, 10000 keys, target 0 | -15.5% | -15.5% | -5.0% |
| set, 0 comment bytes, 10000 keys, target 9999 | -15.5% | -10.3% | -0.7% |
| remove, 0 comment bytes, 10000 keys, target 9999 | -10.0% | -10.1% | -4.8% |
| remove, 0 comment bytes, 1 keys, target -1 | -0.1% | +1.7% | -7.5% |
| remove, 1000000 comment bytes, 1 keys, target -1 | -0.2% | +0.7% | +1.4% |
| remove, 0 comment bytes, 10000 keys, target -1 | -2.1% | +3.2% | +4.8% |
| set, 0 comment bytes, 8 keys, target -1 | +1.8% | -3.4% | +1.7% |
| set, 0 comment bytes, 1 keys, target 0 | +6.1% | -0.3% | +0.1% |

### legacy profile

| Operation / shape | First | Confirmation | Unchanged control |
| --- | ---: | ---: | ---: |
| remove, 0 comment bytes, 1 keys, target 0 | +1.4% | -3.3% | +5.4% |
| remove, 0 comment bytes, 8 keys, target 0 | -7.4% | -0.5% | +1.0% |
| remove, 0 comment bytes, 8 keys, target 7 | -2.3% | -3.6% | +3.7% |
| remove, 0 comment bytes, 32 keys, target 0 | -1.5% | +2.3% | +0.3% |
| remove, 0 comment bytes, 32 keys, target 31 | -0.4% | -4.3% | +3.7% |
| set, 65536 comment bytes, 1 keys, target 0 | -2.3% | -2.2% | +3.4% |
| remove, 65536 comment bytes, 1 keys, target 0 | +0.9% | -2.7% | -0.6% |
| set, 1000000 comment bytes, 1 keys, target 0 | +0.6% | -1.1% | -7.9% |
| remove, 1000000 comment bytes, 1 keys, target 0 | +1.2% | -8.3% | +4.0% |
| set, 0 comment bytes, 10000 keys, target 0 | -13.1% | -16.5% | +3.7% |
| remove, 0 comment bytes, 10000 keys, target 0 | -20.7% | -10.2% | -10.1% |
| set, 0 comment bytes, 10000 keys, target 9999 | -16.4% | -14.6% | -3.0% |
| remove, 0 comment bytes, 10000 keys, target 9999 | -11.5% | -5.1% | -3.7% |
| remove, 0 comment bytes, 1 keys, target -1 | +3.0% | +4.4% | -1.9% |
| remove, 1000000 comment bytes, 1 keys, target -1 | +6.7% | -5.0% | -0.8% |
| remove, 0 comment bytes, 10000 keys, target -1 | -17.7% | -14.0% | +4.4% |
| set, 0 comment bytes, 8 keys, target -1 | -0.1% | +1.3% | -2.3% |
| set, 0 comment bytes, 1 keys, target 0 | +0.1% | +6.7% | +0.3% |

The strongest repeated observations concern wide sets (including both first
and last keys) and some wide removals. The public companion wide fixture also
repeats a reduction larger than its unchanged-binary control. Tiny and
comment-heavy results are mixed; no general speedup is claimed for them.
Single-run regressions remain, including refined small set observations above
6% and the original large-removal outlier below. Absence of a repeated slowdown
is not proof that every workload is regression-free.

## Existing public companion workloads

| Case | First | Confirmation | Unchanged control |
| --- | ---: | ---: | ---: |
| set | +2.6% | +1.5% | +0.5% |
| insert | +0.3% | +2.7% | +2.8% |
| remove | -1.0% | +1.3% | +4.3% |
| wide | -7.7% | -7.1% | -1.8% |
| deep | -3.1% | -4.7% | +0.8% |
| comments | -3.0% | -0.2% | +3.9% |

All refined public-call batches meet the duration minimum. Results apply to
these six complete calls on this machine, not to arbitrary TOML inputs.

## Existing four-case default benchmark

| Case | First | Confirmation | Unchanged control | Final outlier check |
| --- | ---: | ---: | ---: | ---: |
| put_small | -8.9% | +1.9% | -5.3% | -0.2% |
| remove_small | -5.7% | +4.1% | +4.5% | -2.5% |
| put_large | -0.1% | -1.5% | -3.7% | -4.4% |
| remove_large | -1.4% | +9.3% | +3.1% | -4.0% |

The large-removal confirmation regressed by about 9.3%; the first run was
near neutral and a final comparison did not reproduce that regression. This
prompted the additional unchanged-binary control and final check; all four
reports are retained. Small-case batches in this legacy combined benchmark
are short, so those entries are informational, with the dedicated calibrated
fixtures providing more suitable timing evidence. This outlier prevents a
claim of uniformly improved latency.

## Separate storage observations

The instrumented fixture uses 26 data stacks / 27 total regions before reuse
and 23 data stacks / 24 total regions after reuse. This is a count of runtime
regions for **this fixture program**, not a per-call allocation count or a claim
about every embedding application. The region reservation size is unchanged.
Instrumentation uses engine-equivalent checkpoints `3f11133`/`e9ecd6d` and the
older 10,000-call fixture bound; each observation executes one measured call
plus preflight/warmups, so no refined-bound performance is inferred from it.

| Complete instrumented process | Baseline median max RSS (KiB) | Reuse median max RSS (KiB) |
| --- | ---: | ---: |
| source remove 0 10000 0 | 9272 | 6796 |
| legacy remove 0 10000 0 | 9268 | 6832 |
| source set 1000000 1 0 | 6444 | 6324 |
| legacy set 1000000 1 0 | 6436 | 6320 |

Every storage sample, minor/major fault count and runtime stats line is in
[reuse-storage.json](reuse-storage.json), including its producer source and
build flags. These whole-process values include input, expected/preflight output
buffers and runtime startup; they do not isolate per-call parser memory. Region
rewinds can reuse committed pages, so no per-call heap-allocation claim follows.

## Reproduction

Use clean standalone snapshots and the exact pinned compiler. The baseline and
candidate full SHAs above identify the refined experiment. Both must contain
byte-identical `source/tests/profile_costs.goose`; all listed non-engine inputs
must match. From the candidate checkout, use paths to separate snapshots:

```sh
python3 source/tests/measure_reuse.py "$REUSE_BASELINE" "$REUSE_CANDIDATE" \
  --goose "$REUSE_GOOSE" --cpu 6 --calibrate --config /tmp/reuse-config.json
python3 source/tests/measure_reuse.py "$REUSE_BASELINE" "$REUSE_BASELINE" \
  --goose "$REUSE_GOOSE" --cpu 6 --config /tmp/reuse-config.json --output /tmp/reuse-control.json
python3 source/tests/measure_reuse.py "$REUSE_BASELINE" "$REUSE_CANDIDATE" \
  --goose "$REUSE_GOOSE" --cpu 6 --config /tmp/reuse-config.json --output /tmp/reuse-first.json
# Separately start the same comparison for confirmation, with a new output file.
```

The runner rejects mismatched frozen snapshots, scripts, compiler/build settings
and hardware metadata. A deliberately mismatched flags config was rejected
before timing. Undersized samples remain recorded and are marked ineligible.
The original four-case comparator is `source/tests/compare_profiles.py`.
Public-call and storage artifact files embed their original producer source and
full input provenance; reconstruct the two public `ae32` exports, overlay only
the exact candidate editor, and build the identical harness/compiler/flags.
The intentional overlay must not be represented as a passing released-manifest
check. Restore/retain the released snapshot independently.

## Remaining promotion gates

This result justifies retaining a small storage-reuse candidate for review,
not adopting it into frozen releases. Review the mixed timing and single-run
regressions, then require exact-head hosted x86/ARM checks and an approved later
immutable canonical pin before any consumer/parent update. Existing alias
validation used an explicitly isolated export; it is not released adoption.
No alpha or companion tags were retagged and no parent/Honk pins were changed
by this experiment.
