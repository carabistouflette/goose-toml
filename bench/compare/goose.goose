// SPDX-License-Identifier: Apache-2.0
import toml from "../..";
import std;
import os;
import json;

extern fn consume(value: i64) -> i64 = "compare_consume";

fn visit(doc: toml::Document&, stats: i64[18]&) {
    // The same semantic nodes are visited as in the tree based competitors.
    // Goose stores them in a flat owned DOM; keys belong to table children.
    for node, id in doc.nodes {
        stats[0]++;
        if node.parent >= 0 && doc.nodes[node.parent].kind == toml::Kind.Table { stats[7] += toml::key(doc, id).len; }
        if node.kind == toml::Kind.Table { stats[1]++; }
        else if node.kind == toml::Kind.Array { stats[2]++; }
        else if node.kind == toml::Kind.String { stats[3]++; stats[8] += toml::text(doc, id).len; }
        else if node.kind == toml::Kind.Integer { stats[4]++; stats[9] += node.integer; }
        else if node.kind == toml::Kind.Float {
            stats[5]++;
            let bits = float_text::bits_of(node.number);
            stats[16] += ((bits & 0xffffffff) ^ (bits >> 32)) as i64;
            if node.number >= -1000000.0 && node.number <= 1000000.0 { stats[10] += (node.number * 1000.0) as! i64; }
            if node.number < -1000000.0 || node.number > 1000000.0 || bits == 0x8000000000000000 || ((bits & 0x7ff0000000000000) == 0 && (bits & 0xfffffffffffff) != 0) { stats[17]++; }
        }
        else if node.kind == toml::Kind.Boolean { stats[6]++; if node.boolean { stats[11]++; } }
        else if node.kind == toml::Kind.OffsetDateTime { stats[12]++; }
        else if node.kind == toml::Kind.LocalDateTime { stats[13]++; }
        else if node.kind == toml::Kind.LocalDate { stats[14]++; }
        else if node.kind == toml::Kind.LocalTime { stats[15]++; }
        else { abort("unsupported node kind"); }
    }
}
fn decimal(source: u8[:], start: i64, end: i64) -> i64 {
    var value = 0;
    for c in source[start..end] { assert(c >= '0' && c <= '9'); value = value * 10 + c - '0'; }
    return value;
}
fn encode_temporal(doc: toml::Document&, id: i64, out: u8[>..]&) {
    let node = doc.nodes[id];
    let source = toml::text(doc, id);
    let kind = if node.kind == toml::Kind.OffsetDateTime { "offset-datetime" }
        else if node.kind == toml::Kind.LocalDateTime { "local-datetime" }
        else if node.kind == toml::Kind.LocalDate { "local-date" } else { "local-time" };
    var parts: i64[7] = [0; 7];
    if node.kind != toml::Kind.LocalTime {
        parts[0] = decimal(source, 0, 4); parts[1] = decimal(source, 5, 7); parts[2] = decimal(source, 8, 10);
    }
    var at = if node.kind == toml::Kind.LocalTime { 0 } else { 11 };
    if node.kind != toml::Kind.LocalDate {
        parts[3] = decimal(source, at, at + 2); parts[4] = decimal(source, at + 3, at + 5); parts[5] = decimal(source, at + 6, at + 8);
        at += 8;
        if at < source.len && source[at] == '.' {
            at++; var digits = 0;
            while at < source.len && source[at] >= '0' && source[at] <= '9' {
                if digits < 9 { parts[6] = parts[6] * 10 + source[at] - '0'; }
                digits++; at++;
            }
            while digits < 9 { parts[6] *= 10; digits++; }
        }
    }
    out.append("{\"$toml_temporal\":["); json::format_string(out, kind);
    for part in parts { format(out, ",", part); }
    out.push(',');
    if node.kind == toml::Kind.OffsetDateTime {
        var offset = 0;
        if source[at] == '+' || source[at] == '-' {
            offset = decimal(source, at + 1, at + 3) * 60 + decimal(source, at + 4, at + 6);
            if source[at] == '-' { offset = -offset; }
        }
        format(out, offset);
    } else { out.append("null"); }
    out.append("]}");
}
recursive fn encode(doc: toml::Document&, id: i64, out: u8[>..]&) {
    let node = doc.nodes[id];
    if node.kind == toml::Kind.Table || node.kind == toml::Kind.Array {
        let table = node.kind == toml::Kind.Table;
        out.push(if table { '{' } else { '[' });
        var child = node.first;
        while child >= 0 {
            if child != node.first { out.push(','); }
            if table { json::format_key(out, toml::key(doc, child)); }
            encode(doc, child, out);
            child = doc.nodes[child].next;
        }
        out.push(if table { '}' } else { ']' });
    } else if node.kind == toml::Kind.String { json::format_string(out, toml::text(doc, id)); }
    else if node.kind == toml::Kind.Integer { format(out, node.integer); }
    else if node.kind == toml::Kind.Float {
        if node.number == 0.0 && (float_text::bits_of(node.number) >> 63) != 0 { out.append("-0.0"); return; }
        let start = out.len;
        json::format_number(out, node.number);
        var marker = false;
        for c in out[start..] { if c == '.' || c == 'e' || c == 'E' { marker = true; } }
        if !marker { out.append(".0"); }
    }
    else if node.kind == toml::Kind.Boolean { out.append(if node.boolean { "true" } else { "false" }); }
    else { encode_temporal(doc, id, out); }
}
fn step(source: u8[:], doc: toml::Document&, full: bool, total: i64[18]&) -> i64 {
    let error = toml::parse_into(source, doc);
    if error.len > 0 { write_stderr(error); exit(1); }
    let roots = consume(doc.nodes[0].count);
    if full {
        var stats: i64[18] = [0; 18]; visit(doc, stats);
        for count, j in stats { total[j] += count; }
    }
    return roots;
}
fn main() {
    let argv = args();
    if argv.len != 4 { abort("usage: runner INPUT ITERATIONS full|root|decode|full-reuse|root-reuse|write|write-decode"); }
    let iterations, ok = parse_int(argv[2]);
    if !ok || iterations < 1 || iterations > 1000000 { abort("invalid iterations"); }
    let mode = argv[3];
    if mode != "full" && mode != "root" && mode != "decode" && mode != "full-reuse" && mode != "root-reuse" && mode != "write" && mode != "write-decode" { abort("invalid mode"); }
    let reuse = mode == "full-reuse" || mode == "root-reuse";
    let full = mode == "full" || mode == "full-reuse";
    var source: u8[>..] = [];
    if !read_file(argv[1], source) { abort("cannot read input"); }
    var fingerprint: u64 = 14695981039346656037;
    for byte in source { fingerprint = (fingerprint ^ byte) * 1099511628211; }
    if mode == "decode" {
        var doc = toml::Document { .. };
        let error = toml::parse_into(source, doc);
        if error.len > 0 { write_stderr(error); exit(1); }
        var out: u8[>..] = []; encode(doc, 0, out); print(out); return;
    }
    if mode == "write" || mode == "write-decode" {
        var doc = toml::Document { .. };
        let error = toml::parse_into(source, doc);
        if error.len > 0 { write_stderr(error); exit(1); }
        if mode == "write-decode" {
            let output, write_error = toml::serialize(doc);
            if write_error.len > 0 { write_stderr(write_error); exit(1); }
            write_stdout(output); return;
        }
        var serialized_bytes = 0;
        var bytes_total = 0;
        var consumed_total = 0;
        let start = clock_ns();
        for i in iterations {
            let output, write_error = toml::serialize(doc);
            if write_error.len > 0 { write_stderr(write_error); exit(1); }
            serialized_bytes = output.len;
            var edges = 0;
            if output.len > 0 { edges = (output[0] as i64) + output[output.len - 1]; }
            bytes_total += output.len;
            consumed_total += consume(output.len + edges);
        }
        let elapsed = clock_ns() - start;
        print("{\"iterations\":", iterations, ",\"input_bytes\":", source.len,
              ",\"input_fnv64\":\"", fingerprint, "\",\"elapsed_ns\":", elapsed,
              ",\"serialized_bytes\":", serialized_bytes, ",\"output_bytes_total\":", bytes_total,
              ",\"output_edge_total\":", consumed_total - bytes_total, "}");
        return;
    }
    var total: i64[18] = [0; 18];
    var roots = 0;
    var reused = toml::Document { .. };
    let start = clock_ns();
    for i in iterations {
        // Scope cleanup releases each fresh semantic document. Goose's data
        // stacks naturally retain backing pages; no artificial trim is added.
        if reuse { roots += step(source, reused, full, total); }
        else {
            var doc = toml::Document { .. };
            roots += step(source, doc, full, total);
        }
    }
    let elapsed = clock_ns() - start;
    var out: u8[>..] = [];
    format(out, "{\"iterations\":", iterations, ",\"input_bytes\":", source.len,
           ",\"input_fnv64\":\"", fingerprint, "\",\"elapsed_ns\":", elapsed,
           ",\"root_total\":", roots, ",\"stats_total\":[");
    let width = if total[17] != 0 { 17 } else if total[12] != 0 || total[13] != 0 || total[14] != 0 || total[15] != 0 { 16 } else { 12 };
    if total[17] != 0 { total[10] = 0; }
    for count, j in total[..width] { if j > 0 { out.push(','); } format(out, count); }
    out.append("]}"); print(out);
}
