// SPDX-License-Identifier: Apache-2.0
// Test-only adapter: official tagged JSON -> supported construction -> writer.
import toml from "..";
import std;
import json;
import os;
fn insert(doc: toml::Document&, parent: i64, name: const u8[:], array: bool, input: toml::Input) -> i64, u8[>..] {
    if array { return toml::push(doc, parent, input); }
    return toml::put(doc, parent, name, input);
}

recursive fn build(n: json::Node&, doc: toml::Document&, parent: i64, name: const u8[:], array: bool, failure: u8[>..]&) -> i64 {
    var input = toml::Input.Table;
    var container = false;
    var elements = false;
    match n.val {
        Arr a => { input = toml::Input.Array; container = true; elements = true; },
        Obj o => {
            let tag, tagged = json::as_string(json::member(n, "type"));
            if !tagged { container = true; }
            else {
                let value, ok = json::as_string(json::member(n, "value"));
                if !ok || o.count != 2 { failure = str("encoder: invalid tagged scalar"); return -1; }
                if tag == "string" { input = toml::Input.String { value: value }; }
                else if tag == "integer" {
                    if value.len > toml::MAX_NUMBER_BYTES { failure = str("encoder: numeric token exceeds 128 bytes"); return -1; }
                    let integer, valid = parse_int(value);
                    if !valid { failure = str("encoder: invalid integer"); return -1; }
                    input = toml::Input.Integer { value: integer };
                } else if tag == "float" {
                    if value.len > toml::MAX_NUMBER_BYTES { failure = str("encoder: numeric token exceeds 128 bytes"); return -1; }
                    var number = 0.0;
                    if value == "nan" || value == "+nan" || value == "-nan" { number = 0.0 / 0.0; }
                    else if value == "inf" || value == "+inf" { number = 1.0 / 0.0; }
                    else if value == "-inf" { number = -1.0 / 0.0; }
                    else { let parsed, valid = parse_flt(value); if !valid { failure = str("encoder: invalid float"); return -1; } number = parsed; }
                    input = toml::Input.Float { value: number };
                } else if tag == "bool" {
                    if value != "true" && value != "false" { failure = str("encoder: invalid bool"); return -1; }
                    input = toml::Input.Boolean { value: value == "true" };
                } else {
                    let kind = if tag == "datetime" { toml::Kind.OffsetDateTime }
                        else if tag == "datetime-local" { toml::Kind.LocalDateTime }
                        else if tag == "date-local" { toml::Kind.LocalDate }
                        else { toml::Kind.LocalTime };
                    if tag != "datetime" && tag != "datetime-local" && tag != "date-local" && tag != "time-local" {
                        failure = str("encoder: unknown scalar tag"); return -1;
                    }
                    input = toml::Input.DateTime { kind: kind, value: value };
                }
            }
        },
        _ => { failure = str("encoder: expected tagged scalar or container"); return -1; },
    }
    var id = 0;
    if parent < 0 {
        if !container || elements { failure = str("encoder: root must be a table"); return -1; }
    } else {
        let child, error = insert(doc, parent, name, array, input);
        if error.len > 0 { failure = copy(error); return -1; }
        id = child;
    }
    if container {
        var child = n.first;
        while child {
            let ignored = build(child, doc, id, child.key, elements, failure);
            if failure.len > 0 { return -1; }
            child .= child.next;
        }
    }
    return id;
}
fn main() {
    var source: u8[>..] = []; read_stdin(source);
    if source.len > 8388608 { write_stderr("encoder: test input too large\n"); exit(1); }
    // Tagged scalar values are JSON strings. Reject raw numeric tokens before
    // the generic JSON converter can spend work on arbitrary precision input.
    var quoted = false; var escaped = false;
    for c in source {
        if quoted {
            if escaped { escaped = false; }
            else if c == '\\' { escaped = true; }
            else if c == '"' { quoted = false; }
        } else if c == '"' { quoted = true; }
        else if c == '-' || (c >= '0' && c <= '9') { write_stderr("encoder: expected tagged string scalar\n"); exit(1); }
    }
    var nodes: json::Node[>..] = []; var decoded: u8[>..] = [];
    let root, parse_error = json::parse(source, nodes, decoded);
    if parse_error.len > 0 { write_stderr(parse_error); exit(1); }
    guard root else { exit(1); }
    var doc = toml::Document { .. }; toml::init(doc);
    var build_error: u8[>..] = [];
    let id = build(root, doc, -1, "", false, build_error);
    if build_error.len > 0 { write_stderr(build_error); exit(1); }
    let output, write_error = toml::serialize(doc);
    if write_error.len > 0 { write_stderr(write_error); exit(1); }
    write_stdout(output);
}
