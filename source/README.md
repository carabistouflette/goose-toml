# Source-preserving TOML edits

This opt-in module adds and removes named TOML values while copying all bytes
outside the edited token spans. It is separate from the semantic document editor
and canonical writer. It does not change those APIs or enable itself implicitly.

```goose
import toml from "../goose-toml"; // adjust your checkout path
import toml.source.editor;
import std;

fn main() {
    let original = "# project notes\n[dependencies]\nold = {path='../old'} # keep\n";
    let updated, error = toml_source::put(original,
        ["dependencies", "helper"], "{path='../helper'}");
    if error.len > 0 { print(error); return; }
    print(updated);
}
```

Only `toml_source::put` and `toml_source::remove` are supported entry points.
Other declarations are implementation details. Both return `(owned_output,
owned_error)`, with an empty error on success and empty output on every error.
The application owns reading files and atomic publication after success.
Inputs are borrowed for the duration of the call; no references or source ranges
escape into the returned text. Each operation privately indexes the original
source and reparses changed output before returning it.

## Operations

`put(source, path, raw_value, version = toml::Version.V1_0)` replaces a directly
assigned value or inserts a new member. `raw_value` is exactly one TOML value;
it is independently parsed under the selected version, preventing extra
assignments or headers from being injected. Raw spelling is retained. Insertion
uses the deepest existing table body, with quoted relative dotted names as
needed to create missing tables. New lines use the first source newline style,
or LF when the source has none. Existing line endings are copied verbatim.

`remove(source, path, version = toml::Version.V1_0)` removes the assignment or
header token spans belonging to a named subtree, including descendants declared
through dotted assignments or separate table headers. A missing path succeeds
with an owned copy of the original source. Removing a table header also removes
its associated values; unrelated sections remain. Arrays of tables can be
removed as a whole, but paths do not select individual array elements.

Paths contain **decoded table-key segments**, not dotted strings or array
indices. `["a.b", "c"]` selects literal key `a.b`, then `c`. Empty keys, Unicode
and escaped controls are supported; keys must contain valid UTF-8. Inserting
DEL uses `\u007f`, since a literal DEL is prohibited in a TOML quoted key.

The scanner reuses the existing parser's `Reader`, `header`, `assignment_target`
and `value` routines. Its private offsets refer to the original bytes, never
the parsed document's decoded key/text arena. Parser declaration rules and work
budgets apply unchanged. Fixture tests compare the source index's complete
semantic node layout and arena with the ordinary parser.

## Preservation and current limits

Existing comments, indentation, blank lines, quote styles and numeric spellings
outside changed token spans remain byte-for-byte intact. A replaced or removed
multiline value includes its own internal comments. Leading/trailing comments
outside the span remain, including orphaned comments and whitespace-only lines;
the editor does not guess comment ownership or normalize the file.

Removing the last dotted or header-created child can also make its now-empty
**implicit ancestors** disappear semantically: removing `["a", "b"]` from
`a.b=1` leaves a blank line, not an explicit empty `[a]` table. Existing explicit
headers outside the selected subtree remain unchanged.

Edits to an individual child inside an inline table are deliberately unsupported
in this version. They return an error and empty output. Replacing or removing the
entire directly assigned inline table is supported. Replacing a header-declared
table or AoT with a raw value is also unsupported. A source-preserving caller
should report unsupported layouts without falling back to whole-file
normalization. Array ordinals, formatting cleanup and multi-edit plans are not
part of this API.

Each call is bounded independently:

- Original and completed source: at most 1 MiB each.
- Replacement fragment: at most 1 MiB minus four wrapper bytes.
- Path: 1..64 segments and at most 4,096 total decoded key bytes.
- Index: at most 65,536 statements, plus existing parser node/depth/key-work limits.
- At most three bounded parsing passes for insertion/replacement, two for removal.

Outside existing metered parser/index work, scans, path walks and copying are
linear in bounded input plus output size. Storage is O(input bytes + parser
nodes + statements), not a strict allocation-byte budget. Runtime allocation
failure follows Goose's normal policy. Applications must bound repeated calls
and input I/O themselves. No native kernel or runtime dependency is introduced.

## Validation

From a standalone checkout, bootstrap the compiler and official fixtures through
the root project's documented setup/conformance commands, then:

```sh
make -C source format check test property conformance
make -C source sanitize SANITIZER_CC=gcc
make -C source sanitize SANITIZER_CC=clang
make -C source fuzz
```

The opt-in target has its own Makefile and tests. Tests include exact source
comparisons, all ASCII key bytes, source-context cases, 2,405 generated
semantic/preservation checks against Python `tomllib`, and source-index equality
on all pinned TOML 1.0 and 1.1 fixtures. Python comparisons use their shared
TOML 1.0 subset; explicit tests cover version-specific behavior. Sanitizers
instrument both editor tests and the independent model adapter. Fuzzing reuses
all pinned TOML 1.0 fixture inputs and verifies exact Goose assertion crash
capture before its bounded campaign. Its maximum generated input is 1,048,577
bytes, covering the first size beyond the API cap. Linux GCC/Clang are required
for these sanitizer/fuzzer targets. Build output and crash artifacts remain in
`source/.build/`, outside version control.
