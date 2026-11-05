# Parsing and lookup

## Functions and ownership

- `valid_utf8(bytes)` is a supported allocation-free strict UTF-8 check. It accepts Unicode scalars including NUL, BOM and noncharacters; TOML syntax restrictions apply separately during parsing.
- `parse_into(text, doc, version = Version.V1_0)` returns an owned error string, empty on success. It replaces the destination, including on failure. On error the document may be partial: discard it. Messages identify a zero-based byte offset and one-based line/byte column, except input-size and UTF-8 preflight failures, which report byte 0.
- Create the destination as `var doc = toml::Document { .. };`. It is a `root struct` because it owns several independently growable arenas; Goose root structs cannot be returned by value.
- Root is node `0` on success. Nodes use integer indices, which remain valid during arena growth. `first`, `last`, and `next` use `-1` for no link. `count` is the immediate child count; children retain insertion order. Arrays of tables have ordinary array kind and table children.
- `find(doc, parent, key)` looks up **one decoded key**, returning `-1` for a missing key or invalid/non-table parent. Dots in `key` are literal; resolve a dotted path one component at a time. Empty quoted keys are supported. Compare `kind` before reading the corresponding scalar field.
- Kinds: `Table`, `Array`, `String`, `Integer`, `Float`, `Boolean`, `OffsetDateTime`, `LocalDateTime`, `LocalDate`, `LocalTime`. Scalars use `integer`, `number`, `boolean`, or `text(doc, id)` respectively. `key(doc, id)` returns the decoded key of a table child. Array children have no meaningful key.
- Documents own every key and string/date value; the source may be modified or destroyed after parsing. `key` and `text` return borrowed views into the document, so keep it alive and do not mutate or reparse it while retaining those views. They assert that the supplied node index is in range. Reparse invalidates all previous indices and views.
- All integer forms must fit `i64`. No numeric coercion occurs. Decimal floats use Goose's correctly rounded converter; finite overflow is an error, underflow is allowed (including signed zero). Explicit signed `inf` and `nan` are supported.
- Date/time text is calendar-validated and retained as written, including arbitrary fractional precision within the scalar limit. No truncation, timezone conversion, or epoch arithmetic occurs. RFC 3339's lexical second `60` is accepted; leap-second occurrence is not checked against a historical calendar. Literal CRLF inside multiline strings is normalized to LF.

Use `init`, `put`, `push`, `set`, `remove`, `erase` and `compact` for [supported edits](document.md). `serialize(doc)` returns owned TOML text and an owned error, without changing the document. The fields supporting declaration state, hashing, arenas and index are implementation details; do not modify them directly. There is no separate immutable wrapper in this experimental API. Helper functions in the source are not stable API.

## Cost and resource limits

Parsing is linear in input size plus key-index probe/comparison work and bounded scalar conversion. Sealing skips already closed inline subtrees, so total sealing work is linear in nodes. The index uses open addressing at most 50% load with full decoded-key equality checks. It sizes storage by named entries, excluding array elements, and rehashes only indexed entries. `find` hashes O(key bytes), has expected constant probe cost and worst-case linear cost in named entries; application lookups are separate from the per-parse work budget. Deterministic hashes are **not** assumed collision-resistant: a cumulative work budget counts probes, rehash collisions, and compared key bytes, rejecting hostile workloads rather than permitting unbounded quadratic parsing.

- Input: **1 MiB**, checked before UTF-8 validation.
- Nodes: **65,536**, including the root and implicit tables.
- Logical tree depth: **64**, counting every array/table/value edge; dotted paths also have at most 64 components. Arrays of tables consume an extra edge for their element table.
- Bare scalar tokens: **128 bytes**, including numeric and date/time tokens, checked before conversion or a token copy. Strings and keys are bounded by the input cap.
- Key-index work: **16,777,216 units** per parse. Pathological inputs can exhaust this budget below the other limits.

Construction uses the same node, depth and 1 MiB decoded-byte limits; retired nodes and replaced text count until compaction. Each edit has its own key-work budget. Serialization caps output and scanned text at 8 MiB each and meters key comparisons. See [editing limits and invalidation](document.md#ownership-errors-and-limits).

These limits deliberately reject some otherwise valid TOML. They are fixed constants in this version. Recursion follows the checked logical depth. Arena storage is O(input bytes + nodes + index slots); rehashing temporarily copies the old index, and total storage can substantially exceed input size. The input limit is not an exact allocator budget. Reusing a document may retain previously allocated arena capacity. Out-of-memory is governed by Goose's runtime; this API does not promise recovery from allocator failure.


See [document editing](document.md) for editable values and output, or
[source editing](../source/README.md) to retain formatting.
