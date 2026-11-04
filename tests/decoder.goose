// SPDX-License-Identifier: Apache-2.0
// Test-only adapter for the official toml-test tagged JSON protocol.
import toml from "..";
import std;
import json;
import os;
fn tag(out: u8[>..]&, name: u8[:], value: u8[:]) {
    out.append("{\"type\":"); json::format_string(out, name);
    out.append(",\"value\":"); json::format_string(out, value); out.push('}');
}
recursive fn encode(doc: toml::Document&, id: i64, out: u8[>..]&) {
    let n = doc.nodes[id];
    if n.kind == toml::Kind.Table || n.kind == toml::Kind.Array {
        let table = n.kind == toml::Kind.Table;
        out.push(if table { '{' } else { '[' });
        var child = n.first;
        while child >= 0 {
            if child != n.first { out.push(','); }
            if table { json::format_key(out, toml::key(doc, child)); }
            encode(doc, child, out);
            child = doc.nodes[child].next;
        }
        out.push(if table { '}' } else { ']' });
    } else if n.kind == toml::Kind.String { tag(out, "string", toml::text(doc, id)); }
    else if n.kind == toml::Kind.Integer { tag(out, "integer", str(n.integer)); }
    else if n.kind == toml::Kind.Boolean { tag(out, "bool", if n.boolean { "true" } else { "false" }); }
    else if n.kind == toml::Kind.Float {
        var value: u8[>..] = [];
        if n.number != n.number { value.append("nan"); }
        else if n.number > 1.7976931348623157e308 { value.append("inf"); }
        else if n.number < -1.7976931348623157e308 { value.append("-inf"); }
        else { json::format_number(value, n.number); }
        tag(out, "float", value);
    } else {
        var value = str(toml::text(doc, id));
        for &c in value { if c == 't' || c == ' ' { c = 'T'; } else if c == 'z' { c = 'Z'; } }
        let name = if n.kind == toml::Kind.OffsetDateTime { "datetime" }
            else if n.kind == toml::Kind.LocalDateTime { "datetime-local" }
            else if n.kind == toml::Kind.LocalDate { "date-local" } else { "time-local" };
        // toml-test's tagged protocol uses RFC3339 time text even for TOML1.1
        // inputs whose missing seconds are retained lexically by the library.
        let seconds = if n.kind == toml::Kind.LocalDate { -1 } else if n.kind == toml::Kind.LocalTime { 5 } else { 16 };
        if seconds >= 0 && (value.len == seconds || value[seconds] != ':') {
            let complete = str(value[..seconds], ":00", value[seconds..]);
            tag(out, name, complete);
        } else { tag(out, name, value); }
    }
}
fn main() {
    var source: u8[>..] = [];
    read_stdin(source);
    let argv = args();
    var version = toml::Version.V1_0;
    if argv.len > 1 {
        if argv.len != 2 || argv[1] != "--toml=1.1" { write_stderr("decoder: expected --toml=1.1\n"); exit(2); }
        version = toml::Version.V1_1;
    }
    var doc = toml::Document { .. };
    let error = toml::parse_into(source, doc, version);
    if error.len > 0 { write_stderr(error); write_stderr("\n"); exit(1); }
    var out: u8[>..] = [];
    encode(doc, 0, out);
    write_stdout(out); write_stdout("\n");
}
