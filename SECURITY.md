# Security policy

## Supported versions

The project is experimental and has no tagged release. Security fixes target the
latest commit on `main`; there is no support promise for older snapshots. Use an
immutable reviewed commit and the compiler pinned in `GOOSE_REVISION`.

## Report a vulnerability privately

Use [GitHub private vulnerability reporting](https://github.com/carabistouflette/goose-toml/security/advisories/new).
Include the affected full commit, compiler revision, platform, a minimal input,
expected and observed behavior, and relevant sanitizer output. Do not include
credentials or unrelated private data. Please avoid opening a public issue with
exploit details before the report has been assessed and a fix is available.

There is no guaranteed response or remediation deadline. The maintainer will
assess the report, investigate reproducible defects, and coordinate a fix and
public advisory when appropriate.

## Security model

The library parses bytes supplied by its caller. It performs no file, process,
network, or environment I/O. Applications decide where configuration comes from
and how parsed values are used; parsing TOML does not validate application policy.

Input bytes, nodes, logical depth, scalar-token size, and key-index work have
explicit limits documented in [README.md](README.md#cost-and-resource-limits).
The per-parse work limit does not meter application calls to `find`. Successful
documents own their decoded data. Discard partial documents on failure and use only supported editor operations; do not modify implementation fields or
retain borrowed views across edits or reparsing. Editors also cap physical arena
usage, including retired storage. The writer validates reachable structure, text
spans, UTF-8, scalar values and duplicate keys; serialization meters text/key
work and caps output before appending (see [editing documentation](docs/document.md)).

Memory allocation failure and runtime behavior remain governed by the pinned
Goose compiler/runtime. An input-size limit is not an exact allocator budget.
Conformance, differential tests, real collision workloads, sanitizers, and bounded
coverage-guided fuzzing provide evidence; they do not establish exhaustive
correctness or a formal security guarantee.
