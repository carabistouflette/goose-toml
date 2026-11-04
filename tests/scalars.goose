// SPDX-License-Identifier: Apache-2.0
// Batched public-API scalar oracle adapter for scripts/scalar-test.py.
// Input: newline-terminated numeric/boolean tokens, one token per record.
// Output: E or I/B<TAB>value; F<TAB>16 native-order byte hex digits for f64.
// Runtime failures and unexpected accepted kinds are process failures, never E.
import toml from "..";
import std;
import os;

fn emit_scalar(doc: toml::Document&, out: u8[>..]&) {
    let id = toml::find(doc, 0, "v");
    assert(id >= 0 && doc.nodes.len == 2 && doc.nodes[0].count == 1);
    let node = doc.nodes[id];
    if node.kind == toml::Kind.Integer { format(out, "I\t", node.integer, "\n"); }
    else if node.kind == toml::Kind.Float {
        out.append("F\t");
        // Observe the actual f64 bytes directly: the oracle must not depend
        // on the language's float formatter sharing conversion code.
        let value: f64[1] = [node.number];
        for byte in bytes_of(value) {
            out.push("0123456789abcdef"[byte >> 4]);
            out.push("0123456789abcdef"[byte & 15]);
        }
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
