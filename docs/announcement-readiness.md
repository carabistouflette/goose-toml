# Documentation audit

Task: `GL-DOCSTOML-01`. Runtime baseline: published alpha.6,
`e5e5644c45e78e8eb05999978bb4155ea0bbb180`.
This is an audit record, separate from the reader guides.

## Scope

All 19 Markdown files present at alpha.6 were read, along with the maintained
example and the executable commands they reference. No runtime, dependency,
compiler pin, release tag or consumer pin changes are part of this work.

| Files | Disposition |
| --- | --- |
| Root README | Short purpose, pinned quickstart, supported behavior, limits and guide links; API/test detail moved to separate guides |
| `docs/document.md` | Complete immutable-import example; semantic versus source editing distinguished; exact ownership/error/limit contracts retained |
| `source/README.md` | Complete single/batch examples; current inline behavior, snapshot semantics, borrowing, errors and limits; compatibility/history moved to linked pages |
| `docs/platforms.md` | Current root/source x86/ARM coverage distinguished; prerequisites and runtime warning retained |
| `docs/results.md`, `docs/comparison-results.md`, `docs/extended-results.md` | Explicit historical status and immutable reproduction checkout; every original row, slower result and raw artifact retained |
| `docs/comparison-features.md` | Historical semantic-API comparison scoped separately from current source editing; incoming API links repaired |
| `bench/compare/README.md` | Original/extended corpus distinction, quiet-host caveat and result index; executable protocol unchanged |
| `source/tests/performance-followup.md`, `source/tests/results/document-reuse/README.md` | Historical plan/experiment; later alpha.3 shipment identified; original decisions and mixed/regression/control evidence retained |
| `source/tests/results/atomic-batches/README.md`, inline replacement/insertion reports | Historical feature-validation scope; current API and benchmark status linked; no new speed claim |
| `CONTRIBUTING.md`, `SECURITY.md` | Command/limit links repaired; review, reporting and trust contracts retained |
| `CHANGELOG.md` | Version history preserved; performance entries scoped to their measured snapshots |
| `THIRD_PARTY_NOTICES.md`, `vendor/README.md` | Inspected; existing license, compiler/test-tool and optional benchmark dependency descriptions remain accurate, no change needed |

New guides separate API limits, development commands, compatibility details and
historical source-editor evidence from the main reader path. The new local
`examples/source-edit.goose` belongs to this documentation revision, not the
alpha.6 archive. Root test/check targets include it. All library sources remain
byte-identical to the release.

## Validation state

- Markdown local paths/anchors and Git whitespace: checked during preparation.
- Released config example, all four complete guide snippets, and the new
  source-edit example: PASS with the pinned compiler. A fresh public package
  import resolved exactly to alpha.6, with runtime/license/compiler files
  byte-checked against Git blobs; its checkout stayed clean. The new inline
  example asserts exact output. [Commands and output](results/announcement-examples.json).
- Optional setup/conformance/fuzz commands: checked against maintained targets;
  the full historical campaigns are not repeated for prose changes.
- Current parse/write results: queued for one finite, explicitly granted window.
  No build or timing is authorized by this document.

[Frozen input provenance](announcement-readiness-inputs.json) records runtime,
executable harness, compiler binary/source and dependency locks. Existing
[benchmark identities](benchmark-currentness.json) were compared against Git
blobs from alpha.6, not inferred from report dates. All old raw JSON is unchanged.
No alpha.6 source-editor performance claim requires a separate campaign.

Final example commands, measurement outcomes, public documentation revision and
hosted checks will be recorded before the announcement-readiness handoff.
The upstream discussion remains unopened.
