// SPDX-License-Identifier: Apache-2.0
// Batched public-API scalar oracle adapter for scripts/scalar-test.py.
// Input: newline-terminated numeric/boolean tokens, one token per record.
// Output: E for ordinary parse rejection, or I/F/B<TAB>value, one line per record.
// Runtime failures and unexpected accepted kinds are process failures, never E.
import toml from "..";
import std;
import os;
import json;

fn emit_scalar(doc: toml::Document&, out: u8[>..]&) {
    let id = toml::find(doc, 0, "v");
    assert(id >= 0 && doc.nodes.len == 2 && doc.nodes[0].count == 1);
    let node = doc.nodes[id];
    if node.kind == toml::Kind.Integer { format(out, "I\t", node.integer, "\n"); }
    else if node.kind == toml::Kind.Float {
        out.append("F\t");
        if node.number != node.number { out.append("nan"); }
        else if node.number > 1.7976931348623157e308 { out.append("inf"); }
        else if node.number < -1.7976931348623157e308 { out.append("-inf"); }
        else { json::format_number(out, node.number); }
        out.push('\n');
    } else if node.kind == toml::Kind.Boolean { out.append(if node.boolean { "B\ttrue\n" } else { "B\tfalse\n" }); }
    else { write_stderr("scalar adapter: unexpected accepted value kind\n"); exit(2); }
}
fn main() {
    var input: u8[>..] = [];
    read_stdin(input);
    if input.len == 0 || input[input.len - 1] != '\n' {
        write_stderr("scalar adapter: expected newline-terminated input\n"); exit(2);
    }
    let lines = split(input, '\n');
    var doc = toml::Document { .. };
    var out: u8[>..] = [];
    for line, i in lines {
        if i + 1 == lines.len { break; }  // Trailing separator is not another record.
        let source = str("v=", line);
        let error = toml::parse_into(source, doc);
        if error.len > 0 { out.append("E\n"); }
        else { emit_scalar(doc, out); }
    }
    write_stdout(out);
}
