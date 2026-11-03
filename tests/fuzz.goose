// SPDX-License-Identifier: Apache-2.0
import toml from "..";
import std;
var doc = toml::Document { .. };
export fn fuzz_parse(source: const u8[:]) -> i64 {
    let error = toml::parse_into(source, doc);
    if error.len > 0 { return -1; }
    assert(doc.nodes.len >= 1 && doc.nodes[0].parent == -1);
    var edges = 0;
    for node, id in doc.nodes {
        assert(node.key.start >= 0 && node.key.start <= doc.bytes.len);
        assert(node.key.len >= 0 && node.key.len <= doc.bytes.len - node.key.start);
        assert(node.text.start >= 0 && node.text.start <= doc.bytes.len);
        assert(node.text.len >= 0 && node.text.len <= doc.bytes.len - node.text.start);
        assert(toml::valid_utf8(toml::key(doc, id)));
        assert(toml::valid_utf8(toml::text(doc, id)));
        if id > 0 {
            assert(node.parent >= 0 && node.parent < id);
            assert(node.depth == doc.nodes[node.parent].depth + 1 && node.depth <= toml::MAX_DEPTH);
            if doc.nodes[node.parent].kind == toml::Kind.Table {
                assert(toml::find(doc, node.parent, toml::key(doc, id)) == id);
            }
        }
        var count = 0;
        var child = node.first;
        var last = -1;
        while child >= 0 {
            assert(child > id && child < doc.nodes.len && child > last);
            assert(doc.nodes[child].parent == id);
            last = child; child = doc.nodes[child].next; count++;
        }
        assert(count == node.count && last == node.last);
        if node.kind != toml::Kind.Table && node.kind != toml::Kind.Array { assert(count == 0); }
        edges += count;
    }
    assert(edges == doc.nodes.len - 1);
    return doc.nodes.len;
}
// The C host uses this only to prove Goose failures reach libFuzzer and save
// the exact triggering input before the actual campaign starts.
export fn fuzz_assertion_probe(value: i64) { assert(value != 0); }
fn main() {}
