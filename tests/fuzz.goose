// SPDX-License-Identifier: Apache-2.0
import toml from "..";
import std;
// Reuse both arenas across inputs and versions to expose stale parser state.
var doc = toml::Document { .. };
var back = toml::Document { .. };
fn prefix(value: const u8[:], start: const u8[:]) -> bool {
    value.len >= start.len && value[..start.len] == start
}
fn resource_error(error: const u8[:]) -> bool {
    prefix(error, "toml: input exceeds ") || prefix(error, "toml: node limit exceeded") ||
        prefix(error, "toml: nesting limit exceeded") || prefix(error, "toml: key path limit exceeded") ||
        prefix(error, "toml: scalar token exceeds ") || prefix(error, "toml: key lookup work limit exceeded") ||
        prefix(error, "toml: key index work limit exceeded") || prefix(error, "toml: serialization key work limit exceeded") ||
        prefix(error, "toml: serialization text work limit exceeded") || prefix(error, "toml: serialized output exceeds ") ||
        prefix(error, "toml: serialized date/time exceeds ")
}
fn invariant(value: toml::Document&) {
    assert(value.nodes.len >= 1 && value.nodes.len <= toml::MAX_NODES && value.nodes[0].parent == -1);
    assert(value.bytes.len <= toml::MAX_INPUT_BYTES);
    var edges = 0; var text_work = 0;
    for node, id in value.nodes {
        assert(node.key.start >= 0 && node.key.start <= value.bytes.len);
        assert(node.key.len >= 0 && node.key.len <= value.bytes.len - node.key.start);
        assert(node.text.start >= 0 && node.text.start <= value.bytes.len);
        assert(node.text.len >= 0 && node.text.len <= value.bytes.len - node.text.start);
        // Meter scans too: malformed overlapping spans must fail rather than
        // multiplying validation/comparison work across many nodes.
        let bytes = node.key.len + node.text.len;
        assert(bytes <= toml::MAX_WRITE_TEXT_WORK - text_work); text_work += bytes;
        assert(toml::valid_utf8(toml::key(value, id)));
        assert(toml::valid_utf8(toml::text(value, id)));
        if id > 0 {
            assert(node.parent >= 0 && node.parent < id);
            assert(node.depth == value.nodes[node.parent].depth + 1 && node.depth <= toml::MAX_DEPTH);
            if value.nodes[node.parent].kind == toml::Kind.Table {
                assert(toml::find(value, node.parent, toml::key(value, id)) == id);
            }
        }
        var count = 0;
        var child = node.first;
        var last = -1;
        while child >= 0 {
            assert(child > id && child < value.nodes.len && child > last);
            assert(value.nodes[child].parent == id);
            last = child; child = value.nodes[child].next; count++;
        }
        assert(count == node.count && last == node.last);
        if node.kind != toml::Kind.Table && node.kind != toml::Kind.Array { assert(count == 0); }
        edges += count;
    }
    assert(edges == value.nodes.len - 1);
}
fn same_date(kind: toml::Kind, source: const u8[:], result: const u8[:]) {
    if source == result { return; }
    // Serialization converts omitted seconds to :00 without changing the
    // date, separator, offset, case, fractional precision, or local-time kind.
    assert(kind != toml::Kind.LocalDate);
    let minute_end = if kind == toml::Kind.LocalTime { 5 } else { 16 };
    assert(source.len >= minute_end && (source.len == minute_end || source[minute_end] != ':'));
    assert(result.len == source.len + 3);
    assert(result[..minute_end] == source[..minute_end]);
    assert(result[minute_end..minute_end + 3] == ":00");
    assert(result[minute_end + 3..] == source[minute_end..]);
}
recursive fn same(a: toml::Document&, ai: i64, b: toml::Document&, bi: i64, depth: i64, visited: i64&) {
    visited++;
    assert(visited <= toml::MAX_NODES && depth <= toml::MAX_DEPTH);
    let x = a.nodes[ai]; let y = b.nodes[bi];
    assert(x.kind == y.kind && x.count == y.count && x.depth == depth && y.depth == depth);
    assert(toml::key(a, ai) == toml::key(b, bi));
    if x.kind == toml::Kind.Table || x.kind == toml::Kind.Array {
        // Writer and parser preserve sibling order. Walking paired links is
        // linear in nodes and avoids repeated dictionary lookup comparisons.
        var ac = x.first; var bc = y.first;
        while ac >= 0 {
            assert(bc >= 0);
            same(a, ac, b, bc, depth + 1, visited);
            ac = a.nodes[ac].next; bc = b.nodes[bc].next;
        }
        assert(bc == -1);
    } else if x.kind == toml::Kind.Integer { assert(x.integer == y.integer); }
    else if x.kind == toml::Kind.Boolean { assert(x.boolean == y.boolean); }
    else if x.kind == toml::Kind.Float {
        // TOML carries no NaN payload/sign guarantee. Every other bit pattern,
        // including signed zero, subnormals and infinities, must survive.
        if x.number != x.number { assert(y.number != y.number); }
        else { assert(float_text::bits_of(x.number) == float_text::bits_of(y.number)); }
    } else if x.kind == toml::Kind.String { assert(toml::text(a, ai) == toml::text(b, bi)); }
    else { same_date(x.kind, toml::text(a, ai), toml::text(b, bi)); }
}
fn check_version(source: const u8[:], version: toml::Version) -> i64 {
    let error = toml::parse_into(source, doc, version);
    if error.len > 0 { return -1; }
    invariant(doc);
    let output, write_error = toml::serialize(doc);
    if write_error.len > 0 {
        assert(output.len == 0 && resource_error(write_error));
        return doc.nodes.len;
    }
    // Escaping and formatting can expand a valid input past the parser cap.
    // Reparse resource failures are expected; grammar/type/value drift is not.
    let parse_error = toml::parse_into(output, back, toml::Version.V1_0);
    if parse_error.len > 0 { assert(resource_error(parse_error)); return doc.nodes.len; }
    invariant(back);
    assert(doc.nodes.len == back.nodes.len);
    var visited = 0;
    same(doc, 0, back, 0, 0, visited);
    assert(visited == doc.nodes.len);
    return doc.nodes.len;
}
export fn fuzz_parse(source: const u8[:]) -> i64 {
    let strict = check_version(source, toml::Version.V1_0);
    let extended = check_version(source, toml::Version.V1_1);
    // Both versions retain identical resource limits; 1.1 extends 1.0 syntax.
    if strict >= 0 { assert(extended >= 0); }
    return max(strict, extended);
}
// The C host uses this only to prove Goose failures reach libFuzzer and save
// the exact triggering input before the actual campaign starts.
export fn fuzz_assertion_probe(value: i64) { assert(value != 0); }
fn main() {}
