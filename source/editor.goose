// SPDX-License-Identifier: Apache-2.0
namespace toml_source;
import toml;
import std;
import json;

// Builder appends are compiler built-ins; consumer str/copy overloads must
// never turn a validation failure into an empty (successful) diagnostic.
fn owned(bytes: const u8[:]) -> u8[>..] {
    var output: u8[>..] = []; output.append(bytes); return output;
}
const MAX_BYTES:      i64 = 1048576;
const MAX_STATEMENTS: i64 = 65536;
const MAX_PATH_BYTES: i64 = 4096;
const MAX_PATH_DEPTH: i64 = 64;
// Internal, valid only during the call that parsed the original source.
struct Statement {
    node:  i64, context: i64, header: bool,
    start: i64, value_start: i64, end: i64, line_end: i64,
}
// Reuse the parser's grammar and declaration rules, recording source offsets
// before decoded strings enter its arena. Node spans are NOT source positions.
fn index(source: const u8[:], doc: toml::Document&, statements: Statement[>..]&, version: toml::Version) -> u8[>..] {
    statements.clear(); toml::init(doc);
    if source.len > MAX_BYTES { return owned("toml source: input exceeds 1 MiB"); }
    if !toml::valid_utf8(source) { return owned("toml source: invalid UTF-8"); }
    var r = toml::Reader { source: source, version: version, error: [] };
    var current = 0;
    while r.pos < source.len && r.error.len == 0 {
        toml::horizontal(r);
        if toml::peek(r) == '#' { toml::comment(r); }
        if toml::newline(r) { continue; }
        if r.pos == source.len { break; }
        let start = r.pos;
        let header = toml::peek(r) == '[';
        var node = -1; var value_start = start;
        if header { current = toml::header(r, doc); node = current; }
        else {
            node = toml::assignment_target(r, doc, current);
            if node >= 0 {
                toml::horizontal(r); value_start = r.pos;
                toml::value(r, doc, node);
            }
        }
        let end = r.pos;
        toml::horizontal(r);
        if toml::peek(r) == '#' { toml::comment(r); }
        if r.pos < source.len && !toml::newline(r) { toml::fail(r, "expected newline"); }
        if r.error.len > 0 { return owned(r.error); }
        if statements.len == MAX_STATEMENTS { return owned("toml source: statement limit exceeded"); }
        statements.push(Statement { node: node, context: current, header: header,
            start: start, value_start: value_start, end: end, line_end: r.pos });
    }
    return owned(r.error);
}
fn check_path(path: const u8[:][:]) -> u8[>..] {
    if path.len == 0 || path.len > MAX_PATH_DEPTH { return owned("toml source: path needs 1..64 decoded key segments"); }
    var bytes = 0;
    for part in path {
        if part.len > MAX_PATH_BYTES - bytes { return owned("toml source: path exceeds 4096 bytes"); }
        if !toml::valid_utf8(part) { return owned("toml source: invalid UTF-8 key"); }
        bytes += part.len;
    }
    return [];
}
// Each lookup walks a different sibling list along a decoded path, avoiding
// unmetered hash probes. The document is freshly built, never caller-mutated.
fn child(doc: toml::Document&, parent: i64, name: const u8[:]) -> i64 {
    if parent < 0 || doc.nodes[parent].kind != toml::Kind.Table { return -1; }
    var id = doc.nodes[parent].first;
    while id >= 0 {
        if toml::key(doc, id) == name { return id; }
        id = doc.nodes[id].next;
    }
    return -1;
}
fn resolve(doc: toml::Document&, path: const u8[:][:]) -> i64 {
    var id = 0;
    for part in path { id = child(doc, id, part); if id < 0 { return -1; } }
    return id;
}
fn check_value(value: const u8[:], version: toml::Version) -> u8[>..] {
    if value.len > MAX_BYTES - 4 { return owned("toml source: replacement value exceeds limit"); }
    var input = owned("v = "); input.append(value);
    var doc = toml::Document { .. }; var statements: Statement[>..] = [];
    let error = index(input, doc, statements, version);
    if error.len > 0 { return error; }
    if statements.len != 1 || statements[0].header { return owned("toml source: expected exactly one TOML value"); }
    return [];
}
fn newline(source: const u8[:]) -> const u8[:] {
    for byte, at in source {
        if byte == '\n' { return if at > 0 && source[at - 1] == '\r' { "\r\n" } else { "\n" }; }
    }
    return "\n";
}
fn validate_output(output: const u8[:], version: toml::Version) -> u8[>..] {
    var doc = toml::Document { .. };
    return toml::parse_into(output, doc, version);
}
fn splice(source: const u8[:], start: i64, end: i64, replacement: const u8[:], version: toml::Version) -> u8[>..], u8[>..] {
    let kept = source.len - (end - start);
    if replacement.len > MAX_BYTES - kept { return [], owned("toml source: output exceeds 1 MiB"); }
    var output: u8[>..] = [];
    output.append(source[..start]); output.append(replacement); output.append(source[end..]);
    let error = validate_output(output, version);
    if error.len > 0 { return [], owned(error); }
    return output, [];
}
// JSON and TOML share escapes except that DEL must also be escaped in TOML.
fn quoted_key(output: u8[>..]&, name: const u8[:]) {
    if find(name, "\x7f") < 0 { json::format_string(output, name); return; }
    var quoted: u8[>..] = [];
    json::format_string(quoted, name);
    for byte in quoted {
        if byte == 127 { output.append("\\u007f"); } else { output.push(byte); }
    }
}
// Replace a directly assigned value or insert a new member. Existing bytes
// outside the splice, including comments and source spellings, are copied.
fn put(source: const u8[:], path: const u8[:][:], value: const u8[:], version: toml::Version = toml::Version.V1_0) -> u8[>..], u8[>..] {
    let path_error = check_path(path);
    if path_error.len > 0 { return [], owned(path_error); }
    let value_error = check_value(value, version);
    if value_error.len > 0 { return [], owned(value_error); }
    var doc = toml::Document { .. }; var statements: Statement[>..] = [];
    let error = index(source, doc, statements, version);
    if error.len > 0 { return [], owned(error); }
    let target = resolve(doc, path);
    if target >= 0 {
        for statement in statements {
            if !statement.header && statement.node == target {
                return splice(source, statement.value_start, statement.end, value, version);
            }
        }
        return [], owned("toml source: value is not a directly assigned source span");
    }
    // Choose the deepest existing body; dotted names can create missing tables
    // without appending an assignment into the wrong current table.
    var ends: i64[>..] = [];
    for node in doc.nodes { ends.push(-1); }
    ends[0] = 0;
    for statement in statements { ends[statement.context] = statement.line_end; }
    var parent = 0; var context = 0; var depth = 0;
    for part, i in path[..path.len - 1] {
        let next = child(doc, parent, part);
        if next < 0 { break; }
        if doc.nodes[next].kind != toml::Kind.Table { return [], owned("toml source: path crosses a non-table"); }
        if doc.nodes[next].state == toml::State.Sealed || doc.nodes[next].state == toml::State.Inline {
            return [], owned("toml source: editing inside inline tables is unsupported");
        }
        parent = next;
        if ends[parent] >= 0 { context = parent; depth = i + 1; }
    }
    let at = ends[context]; let eol = newline(source);
    var addition: u8[>..] = [];
    if at > 0 && source[at - 1] != '\n' { addition.append(eol); }
    for part, i in path[depth..] {
        if i > 0 { addition.push('.'); }
        quoted_key(addition, part);
    }
    addition.append(" = "); addition.append(value); addition.append(eol);
    return splice(source, at, at, addition, version);
}
// Remove assignment/header token spans belonging to a named subtree. Leading
// and trailing comments, indentation, and surrounding newlines are retained.
fn remove(source: const u8[:], path: const u8[:][:], version: toml::Version = toml::Version.V1_0) -> u8[>..], u8[>..] {
    let path_error = check_path(path);
    if path_error.len > 0 { return [], owned(path_error); }
    var doc = toml::Document { .. }; var statements: Statement[>..] = [];
    let error = index(source, doc, statements, version);
    if error.len > 0 { return [], owned(error); }
    let target = resolve(doc, path);
    if target < 0 { var output: u8[>..] = []; output.append(source); return output, []; }
    var selected: bool[>..] = [];
    for node, id in doc.nodes {
        selected.push(id == target || (node.parent >= 0 && selected[node.parent]));
    }
    var output: u8[>..] = []; var copied = 0; var edits = 0;
    for statement in statements {
        if !selected[statement.node] { continue; }
        output.append(source[copied..statement.start]); copied = statement.end; edits++;
    }
    if edits == 0 { return [], owned("toml source: value is inside an unsupported inline span"); }
    output.append(source[copied..]);
    let output_error = validate_output(output, version);
    if output_error.len > 0 { return [], owned(output_error); }
    return output, [];
}
