# Keep TOML comments and formatting

`toml_source` changes named values while copying bytes outside the edited spans.
It returns owned output and an owned error string; it never reads or writes files.
This guide describes **v0.1.0-alpha.6**, commit
`e5e5644c45e78e8eb05999978bb4155ea0bbb180`.

## Change a value

Save this as `edit.goose` and run it with the [pinned Goose compiler](../docs/platforms.md):

```goose
import toml from "carabistouflette/goose-toml@e5e5644c45e78e8eb05999978bb4155ea0bbb180";
import toml.source.editor;
import std;

fn main() {
    let original = "# project notes\n[dependencies]\nold = {path='../old'} # keep\n";
    let output, error = toml_source::put(original,
        ["dependencies", "helper"], "{path='../helper'}");
    if error.len > 0 { print(error); return; }
    print(output);
}
```

```sh
/path/to/pinned/goose run edit.goose
```

`put(source, path, raw_value, version = toml::Version.V1_0)` replaces an assigned
value or inserts a missing member. The replacement must be exactly one TOML value;
extra assignments or headers are rejected. Its raw spelling is retained.
TOML 1.1 requires an explicit `toml::Version.V1_1` argument.

`remove(source, path, version = toml::Version.V1_0)` removes the named assignment
or table subtree, including descendants written with dotted keys or separate
headers. It can remove a whole array of tables. A missing path succeeds with an
independent owned copy of the validated source.

Paths contain decoded key segments: `["a.b", "c"]` selects literal key `a.b`,
then `c`. They are not dotted strings or array indices. Empty keys, Unicode and
control characters are allowed if their bytes are valid UTF-8; inserted keys
are quoted and escaped as TOML requires.

## Apply a batch

`apply(source, edits, version = toml::Version.V1_0)` returns one result for up to
64 `Edit.Put` or `Edit.Remove` requests:

```goose
import toml from "carabistouflette/goose-toml@e5e5644c45e78e8eb05999978bb4155ea0bbb180";
import toml.source.editor;
import std;

fn main() {
    let original = "[package]\nname = 'old'\n[dependencies]\nold = 1\n";
    let name_path: (const u8[:])[2] = ["package", "name"];
    let old_path: (const u8[:])[2] = ["dependencies", "old"];
    let edits: toml_source::Edit[2] = [
        toml_source::Edit.Put {path: name_path, value: "'renamed'"},
        toml_source::Edit.Remove {path: old_path},
    ];
    let output, error = toml_source::apply(original, edits);
    if error.len > 0 { print(error); return; }
    print(output);
}
```

Every request selects the **original snapshot**. A later request cannot target
something created by an earlier one. Equal paths and ancestor/descendant paths
are rejected, even when missing. Independent siblings under a shared missing
prefix are allowed. Insertions sharing an original offset appear in request order.

Requests borrow paths and replacement bytes until the call returns. Bind path
arrays before creating requests, finish growing backing arrays before borrowing
them, and explicitly type request arrays as `Edit[N]`.

## What is preserved

Comments, spacing, line endings, quoting and numeric spellings outside changed
spans remain byte-for-byte intact. Comments inside a replaced multiline value
belong to that value and are removed with it. Outside comments and blank lines
remain, even when orphaned. Removing the last child of an implicit table can
make that table disappear semantically; explicit unrelated headers remain.

Ordinary insertion uses the closest existing table body and quoted relative
dotted names. Added lines use the source's first newline style, or LF if none.

Alpha.5 adds replacement of values inside inline tables. Alpha.6 adds missing
inline members, inserted just after the closest literal table's opening brace,
before its original whitespace or comments. For example, putting value `2` at
`["v", "new"]` in `v={old=1}` produces `v={"new" = 2, old=1}`. Missing prefixes
can use relative dotted keys. Entries inserted at the same brace follow batch
request order; sequential `put` calls can therefore produce a different order.
Existing members and trailing commas are copied. Replacement fragments must
also be valid in their final context, including any whitespace/comment suffix.

Individual inline-member removal, array-element selection, replacement of a
header-declared table/AoT, and formatting cleanup are unsupported. An implicit
inline table introduced only by dotted keys has no complete value span to
replace. Replacing or removing the whole directly assigned outer inline table
is supported. Report unsupported layouts rather than silently regenerating a file.

## Errors and limits

Success returns an empty error. **Every failure returns empty output** and an
owned diagnostic. Inputs are borrowed only for the call; no input views escape.
Applications decide how to publish a successful result atomically. No partial
batch is returned. Empty batches and all-missing removals still validate source.

Batch validation proceeds through count/path/budget/conflict checks, replacement
fragments, original source, span planning, and output validation. This stage
order determines error precedence. Request-specific errors identify zero-based
`batch edit N`; source, aggregate-budget, output-size and final-parse errors
apply to the whole batch.

| Bound | Default operations |
| --- | --- |
| Original and final source | 1 MiB each |
| Replacement fragment | 1 MiB minus the four-byte parse wrapper |
| Decoded path | 1–64 segments, 4,096 combined bytes |
| Batch | 64 requests; 1 MiB total decoded paths plus raw values |
| Source index | 65,536 statements, plus [parser limits](../docs/api.md#cost-and-resource-limits) |

Inline discovery has its own parser work/node/depth budgets, so it can reject a
source that the initial parse accepted. Changed output is parsed before return.
A batch shares source indexing and final validation; replacement fragments and
selected inline owners need additional parsing. Bounded lookup can cost
O(edits × nodes), conflict checks O(edits² × path segments), and span sorting
O(spans log spans). Storage grows with bounded input, nodes, statements and
output. These bounds are not an exact allocation budget; allocation failure
follows the pinned Goose runtime's policy. Applications must bound repeated calls.

## Compatibility and development

`legacy_set` and `legacy_remove` provide the strict TOML 1.0 profile used by
[goose-toml-edit](https://github.com/carabistouflette/goose-toml-edit).
Their [separate contract](docs/legacy.md) retains historical output/error bytes,
larger path allowance, insertion rules and rejection of inline children.
The profile is available from alpha.2 onward; alpha.1 does not contain it.
Other declarations in the implementation are private.

See [development commands](../docs/development.md#source-editor),
[historical validation and measurements](docs/history.md), and
[benchmark status](../docs/benchmarks.md). Historical timings do not describe
alpha.6 performance. This documentation revision also adds the runnable local
example [examples/source-edit.goose](../examples/source-edit.goose); that file
is not in the alpha.6 tag.
