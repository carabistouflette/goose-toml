# Source editor performance follow-up

**Historical preparation plan.** The terminal-Document reuse experiment later
shipped in alpha.3. The trace and proposed gates below refer to the stated de7
baseline, not current alpha.6 behavior. See the [experiment record](results/document-reuse/README.md)
and [current benchmark status](../../docs/benchmarks.md).

This is a preparation checkpoint, based on immutable canonical
`de7dfe092f6d72811417355044e5d024d5600613`. It adds a diagnostic fixture driver
and a proposed experiment. It changes no engine code, dependency pin or release.
The active wrapper/Honk publication does not depend on this follow-up.

## What the evidence establishes

The existing default-profile report is a comparison against alpha.1. The
companion comparison is a different workload against legacy `cedb2c3`; its
percentages cannot be substituted for the default-profile results. The initial
30-call companion series and longer-loop confirmation vary substantially on the
shared host. They identify workloads to investigate, not a reproduced stable
cause. A fresh paired baseline/candidate experiment is the first gate before
implementing or claiming an optimization. No new timing campaign is recorded
by this checkpoint; smoke timings are not performance evidence.

## Storage and copy trace

Reviewed [the engine](../editor.goose), its generated standalone C, and pinned
Goose `eadca409f68210893f366e60d0c2f0dc29a339be` runtime sources:
`src/runtime/runtime.h` (`gs_stack_block`) and
`src/runtime/runtime_impl.h` (`gs_reserve_region`).

| Stage | Behavior at the de7 baseline | Consequence to investigate |
| --- | --- | --- |
| Fragment check, set only | Parses synthetic `x = ` plus value for legacy; default retains its own fragment policy | Both legacy implementations validate fragments; no extra pass is inferred merely from consolidation |
| Source index | Builds a private Document and statement source offsets | Each statement includes context needed for default insertion |
| Lookup | Walks bounded sibling lists | Wide late-key lookup has more comparisons than legacy hash lookup; changes here require a separate adversarial-work analysis |
| Removal | Builds one selected flag per parsed node before copying spans | Linear setup can dominate tiny shallow removals; avoids repeated ancestor walks on larger subtrees |
| Splice | Copies prefix, replacement and suffix into owned output | Generated C writes directly into its caller-provided output region; a full intermediate copy per helper return is not established |
| Output validation | Creates a new Document while the source Document is still in scope | Separate nodes, decoded bytes and index scratch storage is initialized and touched |
| Companion output adaptation | Completes tuple, then clears/appends caller output | Legacy also owned-copied the completed result; attributing a slowdown solely to adapter copying is unsupported |

Goose reserves data-stack regions for a thread program at startup and rewinds
scratch tops for reuse. A fresh Document is therefore **not proof of a new heap
allocation or mapping on each call**. Possible effects include number of scratch
regions, page commitment/first touch, initialization, memory locality and peak
live parser storage. Count and measure those separately from elapsed time.

For generated-code inspection, from the canonical repository:

```sh
GOOSE=/path/to/pinned/goose
"$GOOSE" source/tests/profile_costs.goose --standalone -O2 -o .build/profile-costs.c
```

Inspect the success path separately from error-diagnostic movement. Generated
code is retained only in ignored `.build/`; it is not a portable public ABI.

## Focused fixture driver

[profile_costs.goose](profile_costs.goose) calls only supported entry points.
Its arguments are `profile operation padding nodes target iterations warmups`.
Profiles are `source`/`legacy`; operations `set`/`remove`. Target `-1` selects a
missing key; other targets select a zero-based key in the generated document.
The fixture creates exact expected bytes independently, including the different
root insertion anchors. It verifies full output before and after timing, checks
status/length and a constant-cost checksum during measurement, and bounds every
argument and final input/output size. Fixture creation and full-byte comparisons
are outside the timed loop. This driver always executes a full preflight;
`warmups=0` still measures calls after that preflight, not cold first use.
`warmups` counts additional calls. The endpoint checksum cannot detect same-length middle-byte corruption within
an individual timed call; keep the full pre/post comparisons and independent
correctness suites. Expected/preflight builders remain live; account for
that when interpreting whole-process memory counters.

Build and smoke execution (one iteration; no timing conclusion):

```sh
/path/to/pinned/goose build source/tests/profile_costs.goose --cc gcc -O2 -o .build/profile-costs
.build/profile-costs legacy remove 0 8 0 1 0
.build/profile-costs source set 1000000 1 0 1 0
```

Proposed experiment matrix; avoid the Cartesian product, which could exceed
1 MiB when large commentary and many keys are combined:

| Purpose | Padding bytes | Keys | Target | Operation |
| --- | ---: | ---: | --- | --- |
| Small removal setup | 0 | 1, 8, 32 | first, last | remove |
| Comment scaling | 0, 65536, 1000000 | 1 | first | set, remove |
| Wide lookup/storage | 0 | 10000 | first, last | set, remove |
| Validated no-op | 0 or 1000000 | 1 | missing | remove |
| Wide no-op | 0 | 10000 | missing | remove |
| Insertion sanity | 0 | 8 | missing | set |

Run each profile against **the same profile** in a baseline and candidate.
Different policy profiles are not interchangeable performance baselines. Use
the full immutable SHA of this reviewed fixture-bearing preparation checkpoint
as the baseline: public `de7` has the same engine but does not contain this
driver. Record that SHA before the campaign and verify the baseline engine
against `de7`. Require the driver blob/hash to be identical in the optimization
candidate; record any overlay explicitly rather than claiming raw `de7` ran it.
Retain the existing four-case default and six-case public companion workloads
as acceptance comparisons; this fixture supplements them.

## Proposed minimal experiment

The first implementation candidate is terminal reuse of the original Document
for final `parse_into`, shared by both profiles. This is a proposal, not an
implemented or measured improvement. Keep lookup, selected bitmap, quoting,
statement representation, fragment parsing and wrapper ownership unchanged.

Only reuse the Document after all node traversal, insertion-anchor selection,
subtree selection and source copying have finished. The completed output owns
its bytes and does not borrow Document arena storage. No old node ID, arena view
or statement-to-node access may occur after reparse clears the Document. Check
all terminal paths separately:

- Replacing a direct assignment through `splice`.
- Inserting through `splice`.
- Removing an existing subtree after the copy loop.
- Legacy missing removal, which must still reparse its owned source copy.
- Default missing removal, which must retain its fast validated owned-copy path.

This suggests passing the already-created Document to the private final
validation helper. Preserve public signatures, strict version selection,
validation/error precedence, limits and owned-output behavior. Avoid API-wide
scratch objects, caller caches, extra engines, weakened validation or skipped
parsing. Do not combine bitmap/lookup changes into this first experiment.

## Falsifiable predictions and measurements

1. **Terminal parser scratch contributes:** reusing the Document should reduce
   separate parser scratch-region use or touched-page high-water marks. A timing
   improvement is a separate prediction; reject a speed claim if it is absent.
2. **Removal bitmap setup contributes:** tiny removals may remain slower after
   Document reuse. If attribution is needed later, measure setup independently
   using disposable instrumentation; do not ship alternate removal semantics.
3. **Copy bandwidth or page/cache effects dominate comments:** time should scale
   with preserved bytes. A parser-storage change alone may leave that slope
   unchanged. Full-operation bytes copied must be traced rather than inferred
   from function-call depth.
4. **Host/first-call sensitivity contributes:** longer warm batches and reversed
   paired order should change or narrow the observed ratios. Failure to repeat
   a slowdown is a limitation, not evidence that a candidate fixed it.

For a later campaign: build both clean immutable snapshots with one unchanged
fixture source, pinned compiler and C flags. Record script/source/compiler and
binary hashes, CPU model/affinity, UTC bounds, input/output sizes, warmups,
iteration counts and every sample. Use at least nine alternating/shuffled paired
rounds and a separately started confirmation. Start calibration at 1000 calls for small cases. Calibrate both small and large
batches, then freeze counts and a minimum measured duration before recording
the campaign; split into repeated batches if the driver's 10000-call cap is too
short. Proposed initial criteria are at least 10 ms per recorded batch, a 5% median
speed benefit and explicit review of any workload regression above 5%; freeze
these or justified alternatives before timing. Estimate baseline variability
with paired unchanged-binary runs. Do not claim a
benefit smaller than the observed noise; require a separately started repeat
to agree before describing an improvement. Report cold
first-use separately from warm repeated calls. A separate cold-path harness is
required: use a fresh process with no preflight invocation, time its first public
call, then check full output against the expected bytes after the measured call.
Do not label this driver's zero-additional-warmup result as cold latency. Retain the original samples,
rejected hypotheses and regressions; no exclusive-host or universal speed claim.

Collect generated-code stack/region counts and, where available, page-fault/RSS
or profiler observations in separate instrumented runs. Whole-process counters
include fixture construction, compiler runtime startup and expected-output
storage. They cannot by themselves prove per-call allocator savings.

## Correctness and adoption gates

Before an optimization is eligible for publication:

- Run unchanged default and legacy exact-byte suites, source model, all pinned
  source-index fixtures and combined size/depth/node/collision limits.
- Repeat the 5134-call frozen legacy differential on the exact new binary; record
  clean snapshot and source/binary identities before and after. Old-pin evidence
  does not approve a new engine.
- Exercise replacement/insertion/removal/no-op, multiline values and scattered
  headers, arrays of tables, inline-table/traversal rejection, UTF-8 and fragment
  precedence, controls, CRLF, exact caps and malformed completed output.
- Preserve source/value/path/output aliasing through the actual public companion
  adapter, hostile consumer overload protection, and empty output on failure.
- Pass GCC/Clang ASan/UBSan, bounded fuzzing and exact-head x86/ARM hosted checks.
- Obtain independent reviews of lifetime/order and measurement correctness.
- Keep a candidate only if repeat measurements support its stated benefit and
  all material regressions are explicitly reviewed. A memory-only improvement
  must be reported as memory evidence, not a speedup.
- Use a later reviewed immutable commit/version and owner-coordinated consumer
  acceptance. Preserve all existing release tags and parent pins during work.

## Preparation verification

The fixture is intended for direct invocation; adding it does not change the
existing Makefile, engine or release gates. Existing CI formatting checks
will see the new fixture; the timing matrix is not added to CI. Preparation checks are
format/type validation plus bounded JIT, optimized and debug smoke executions
covering both profiles, all operations, missing targets and the largest comment
fixture. Smoke samples prove expected bytes and driver execution only.
