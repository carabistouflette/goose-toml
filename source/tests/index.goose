// SPDX-License-Identifier: Apache-2.0
import toml from "../..";
import toml.source.editor;
import std;
import os;
fn main() {
    let argv = args(); let version = if argv.len > 1 && argv[1] == "1.1" { toml::Version.V1_1 } else { toml::Version.V1_0 };
    var input: u8[>..] = []; read_stdin(input);
    var parsed = toml::Document { .. }; var indexed = toml::Document { .. };
    var statements: toml_source::Statement[>..] = [];
    let error = toml::parse_into(input, parsed, version);
    let index_error = toml_source::index(input, indexed, statements, version);
    assert((error.len == 0) == (index_error.len == 0));
    if error.len > 0 { print("0"); return; }
    assert(parsed.nodes.len == indexed.nodes.len && parsed.bytes == indexed.bytes);
    for a, id in parsed.nodes {
        let b = indexed.nodes[id];
        assert(a.kind == b.kind && a.state == b.state && a.parent == b.parent && a.first == b.first && a.last == b.last && a.next == b.next);
        assert(a.depth == b.depth && a.count == b.count && a.integer == b.integer && a.boolean == b.boolean);
        assert(a.number == b.number || (a.number != a.number && b.number != b.number));
        assert(toml::key(parsed, id) == toml::key(indexed, id) && toml::text(parsed, id) == toml::text(indexed, id));
    }
    if toml::find(parsed, 0, "__source_edit_missing_9e08921") < 0 {
        let unchanged, remove_error = toml_source::remove(input, ["__source_edit_missing_9e08921"], version);
        assert(remove_error.len == 0 && unchanged == input);
    }
    print("1");
}
