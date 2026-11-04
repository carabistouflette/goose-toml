// SPDX-License-Identifier: Apache-2.0
namespace toml;
import std;

let MAX_OUTPUT_BYTES = 8388608;
let MAX_WRITE_TEXT_WORK = 8388608;
root struct Writer {
    output:    u8[>..], error: u8[>..], seen: bool[>..], names: i64[>..], name_hashes: u64[>..],
    text_work: i64 = 0, key_work: i64 = 0,
}
fn write_fail(w: Writer&, message: const u8[:]) {
    if w.error.len == 0 { w.error = str("toml: ", message); }
}
fn write_bytes(w: Writer&, value: const u8[:]) {
    if w.error.len > 0 { return; }
    if value.len > MAX_OUTPUT_BYTES - w.output.len { write_fail(w, "serialized output exceeds 8 MiB"); return; }
    w.output.append(value);
}
fn write_byte(w: Writer&, value: u8) {
    if w.error.len > 0 { return; }
    if w.output.len == MAX_OUTPUT_BYTES { write_fail(w, "serialized output exceeds 8 MiB"); return; }
    w.output.push(value);
}
fn checked_span(w: Writer&, doc: Document&, span: Span) -> bool {
    if span.start < 0 || span.len < 0 || span.start > doc.bytes.len || span.len > doc.bytes.len - span.start {
        write_fail(w, "invalid text span"); return false;
    }
    // Charge before scanning: forged overlapping spans cannot multiply CPU work.
    if span.len > MAX_WRITE_TEXT_WORK - w.text_work { write_fail(w, "serialization text work limit exceeded"); return false; }
    w.text_work += span.len;
    if !valid_utf8(doc.bytes[span.start..span.start + span.len]) { write_fail(w, "invalid UTF-8 text"); return false; }
    return true;
}
fn write_quoted(w: Writer&, value: const u8[:]) {
    write_byte(w, '"');
    for c in value {
        if w.error.len > 0 { return; }
        if c == '"' { write_bytes(w, "\\\""); }
        else if c == '\\' { write_bytes(w, "\\\\"); }
        else if c == '\n' { write_bytes(w, "\\n"); }
        else if c == '\r' { write_bytes(w, "\\r"); }
        else if c == '\t' { write_bytes(w, "\\t"); }
        else if c == 8 { write_bytes(w, "\\b"); }
        else if c == 12 { write_bytes(w, "\\f"); }
        else if c < 32 || c == 127 {
            write_bytes(w, "\\u00");
            write_byte(w, "0123456789ABCDEF"[c >> 4]); write_byte(w, "0123456789ABCDEF"[c & 15]);
        } else { write_byte(w, c); }
    }
    write_byte(w, '"');
}
fn write_name(w: Writer&, doc: Document&, id: i64) {
    let n = doc.nodes[id];
    let name = doc.bytes[n.key.start..n.key.start + n.key.len];
    let h = key_hash(n.parent, name);
    var slot = (h & ((w.names.len - 1) as u64)) as i64;
    while w.names[slot] >= 0 {
        w.key_work++;
        if w.key_work > MAX_KEY_WORK { write_fail(w, "serialization key work limit exceeded"); return; }
        let other = doc.nodes[w.names[slot]];
        if w.name_hashes[slot] == h && other.parent == n.parent && other.key.len == name.len {
            w.key_work += name.len;
            if w.key_work > MAX_KEY_WORK { write_fail(w, "serialization key work limit exceeded"); return; }
            if doc.bytes[other.key.start..other.key.start + other.key.len] == name { write_fail(w, "duplicate table key"); return; }
        }
        slot = (slot + 1) & (w.names.len - 1);
    }
    w.names[slot] = id;
    w.name_hashes[slot] = h;
    write_quoted(w, name); write_bytes(w, " = ");
}
fn write_date(w: Writer&, value: const u8[:], kind: Kind) {
    let actual, ok = datetime(value, Version.V1_1);
    if !ok || actual != kind { write_fail(w, "invalid date/time value"); return; }
    // Always emit TOML 1.0, adding seconds omitted in TOML 1.1.
    let minute_end = if kind == Kind.LocalTime { 5 } else { 16 };
    let omitted = kind != Kind.LocalDate && (value.len == minute_end || value[minute_end] != ':');
    if value.len > MAX_NUMBER_BYTES - (if omitted { 3 } else { 0 }) {
        write_fail(w, "serialized date/time exceeds 128 bytes"); return;
    }
    if omitted {
        write_bytes(w, value[..minute_end]); write_bytes(w, ":00"); write_bytes(w, value[minute_end..]);
    } else { write_bytes(w, value); }
}
recursive fn write_value(w: Writer&, doc: Document&, id: i64, parent: i64, depth: i64) {
    if w.error.len > 0 { return; }
    if id < 0 || id >= doc.nodes.len || depth > MAX_DEPTH { write_fail(w, "invalid node link or nesting depth"); return; }
    if w.seen[id] { write_fail(w, "repeated or cyclic node link"); return; }
    w.seen[id] = true;
    let n = doc.nodes[id];
    if n.parent != parent || n.depth != depth { write_fail(w, "invalid node parent or depth"); return; }
    if !checked_span(w, doc, n.key) || !checked_span(w, doc, n.text) { return; }
    if parent >= 0 && doc.nodes[parent].kind == Kind.Table { write_name(w, doc, id); }
    if n.kind == Kind.Table || n.kind == Kind.Array {
        let table = n.kind == Kind.Table;
        if id != 0 { write_byte(w, if table { '{' } else { '[' }); }
        var child = n.first; var last = -1; var count = 0;
        while child != -1 {
            if w.error.len > 0 { return; }
            if child <= 0 || child >= doc.nodes.len || count >= MAX_NODES { write_fail(w, "invalid child link"); return; }
            if count > 0 && id != 0 { write_bytes(w, ", "); }
            write_value(w, doc, child, id, depth + 1);
            if id == 0 { write_byte(w, '\n'); }
            last = child; child = doc.nodes[child].next; count++;
        }
        if count != n.count || last != n.last { write_fail(w, "invalid container count or last link"); return; }
        if id != 0 { write_byte(w, if table { '}' } else { ']' }); }
        return;
    }
    if n.first != -1 || n.last != -1 || n.count != 0 { write_fail(w, "scalar has child links"); return; }
    if n.kind == Kind.String || date_kind(n.kind) {
        let value = doc.bytes[n.text.start..n.text.start + n.text.len];
        if n.kind == Kind.String { write_quoted(w, value); } else { write_date(w, value, n.kind); }
    } else if n.kind == Kind.Integer { write_bytes(w, str(n.integer)); }
    else if n.kind == Kind.Boolean { write_bytes(w, if n.boolean { "true" } else { "false" }); }
    else if n.kind == Kind.Float {
        let negative = (float_text::bits_of(n.number) >> 63) != 0;
        if n.number != n.number { write_bytes(w, if negative { "-nan" } else { "nan" }); }
        else if n.number - n.number != 0.0 { write_bytes(w, if negative { "-inf" } else { "inf" }); }
        else if n.number == 0.0 { write_bytes(w, if negative { "-0.0" } else { "0.0" }); }
        else {
            let value = str(n.number);
            var marker = false;
            for c in value { if c == '.' || c == 'e' || c == 'E' { marker = true; } }
            write_bytes(w, value); if !marker { write_bytes(w, ".0"); }
        }
    } else { write_fail(w, "unsupported value kind"); }
}

// Semantic TOML 1.0 output. Comments, declaration style and State are not kept.
// Tables nested below root use inline syntax; arrays of tables use inline values.
// On failure the output is empty. Document storage and IDs remain unchanged.
fn serialize(doc: Document&) -> u8[>..], u8[>..] {
    if doc.nodes.len == 0 || doc.nodes.len > MAX_NODES || doc.bytes.len > MAX_INPUT_BYTES {
        return [], str("toml: invalid document size");
    }
    let root = doc.nodes[0];
    if root.kind != Kind.Table || root.parent != -1 || root.depth != 0 || root.next != -1 {
        return [], str("toml: root must be a document table");
    }
    var w = Writer { output: [], error: [], seen: [], names: [], name_hashes: [], .. };
    for i in doc.nodes.len { w.seen.push(false); }
    var slots = 16;
    while slots < doc.nodes.len * 2 { slots *= 2; }
    for i in slots { w.names.push(-1); w.name_hashes.push(0); }
    write_value(w, doc, 0, -1, 0);
    if w.error.len > 0 { return [], copy(w.error); }
    return copy(w.output), [];
}
