# Construct, edit and write TOML

The supported semantic workflow is parse or initialize a document, inspect it,
modify values through editor functions, and serialize it. Comments, whitespace,
declaration style and numeric spellings are not preserved. Automatic struct
mapping and source-format editing are outside this API.

```goose
import toml from "../goose-toml"; // adjust to your checkout
import std;

fn main() {
    var doc = toml::Document { .. };
    toml::init(doc); // node 0 is an empty root table
    let server, server_error = toml::put(doc, 0, "server", toml::Input.Table);
    if server_error.len > 0 { print(server_error); return; }
    let port, port_error = toml::put(doc, server, "port", toml::Input.Integer { value: 8080 });
    if port_error.len > 0 { print(port_error); return; }
    let output, error = toml::serialize(doc);
    if error.len > 0 { print(error); return; }
    print(output); // "server" = {"port" = 8080}
}
```

`Input` variants are `Table`, `Array`, `String { value }`, `Integer { value }`,
`Float { value }`, `Boolean { value }`, and `DateTime { kind, value }`.
Text arguments are borrowed for the call and copied into document storage.
Containers start empty. `DateTime.kind` must be one of the four date/time kinds;
its text must be valid for that kind under TOML 1.1. No timezone conversion or
fraction truncation occurs. Strings and keys must contain valid UTF-8; decoded
control characters are allowed and escaped when written.

| Operation | Result and behavior |
| --- | --- |
| `init(doc)` | Clear storage and create an empty table root. |
| `put(doc, table, key, input)` | `(id, error)`; insert or replace one decoded key. Dots are literal. Replacement preserves that node's ID and sibling position. |
| `push(doc, array, input)` | `(id, error)`; append one array element. |
| `set(doc, id, input)` | Error string; replace a value and retire its old descendants. Root may only be replaced with a table. |
| `remove(doc, table, key)` | `(removed, error)`; unlink a member and retire its subtree. Missing keys return `false` and no error. |
| `erase(doc, array, ordinal)` | `(removed, error)`; zero-based array position, not node ID. Out-of-range positions return `false` and no error. |
| `serialize(doc)` | `(owned_text, error)`; valid TOML 1.0, or empty text on error. Does not modify the document. |
| `compact(doc)` | Error string; serialize/reparse to reclaim retired storage. All IDs and views expire. An output exceeding the parser's 1 MiB cap is rejected before reparsing. |

Empty error strings mean success. Failed `put`/`push` return ID `-1`.
Editor calls require a document created by `init` or successful `parse_into`,
with implementation fields unmodified. Parsed inline tables can be edited:
their source-declaration restrictions do not restrict semantic editing.

## Ownership, errors and limits

Node IDs survive arena growth and edits to other nodes. Replacing a container
retires all descendants; removing a subtree retires every ID in it. Retired IDs
are never reused before initialization, reparsing or compaction. `set` preserves
the replaced node's ID. Borrowed key/text views can expire on any edit; copy text
you need to keep before editing. Do not pass a view into document storage to an
operation that can grow that storage; copy it first.

An editor failure may leave a partial document. Discard or reinitialize it;
transactional rollback is not promised. Serialization failures leave the input
document unchanged and return empty output. Direct edits to node links, spans,
hashes or arena fields are unsupported. Serialization nevertheless checks the
reachable tree and rejects invalid links, cycles, duplicate table keys, invalid
spans/UTF-8, invalid dates and inconsistent counts/depth.

Physical storage is limited to 65,536 nodes and 1 MiB decoded key/value bytes;
replaced text and retired nodes count until compaction. Logical depth is 64.
Date/time inputs are capped at 128 bytes, preserving fractional precision within
that cap. Each editor lookup has a 16,777,216-unit probe/compared-byte budget.
Repeated application calls are not covered by one cumulative budget. Removing
a table member scans its child list; it is linear in member count plus compared
key bytes. Retiring a container is linear in its subtree.

Serialization caps output at 8 MiB and scanned text at 8 MiB (including repeated
or overlapping spans), with a separate 16,777,216-unit key-work budget. Its
temporary visited/index storage is proportional to physical nodes, including
retired nodes. Output may exceed the parser's 1 MiB input cap, so a successful
serialization does not guarantee successful reparse/compaction by this library.
These are work/storage bounds, not an exact allocator budget or recovery promise
for allocation failure.

## Output and version conversion

Every key is quoted. Root members use one assignment per line. Nested tables
use inline tables; arrays of tables use arrays of inline tables. This handles
all semantic TOML kinds without retaining source declaration state. Finite
floats round-trip as binary64, including negative zero. NaN payload/sign identity
is not promised. Infinities and NaNs use explicit TOML tokens.

The writer always emits TOML 1.0-compatible syntax. TOML 1.1 escapes are emitted
as ordinary Unicode or 1.0 escapes, and omitted time seconds become `:00`.
Date/time text otherwise retains its validated spelling and fractional digits.
Writing does not alter the original document's lexical text.
