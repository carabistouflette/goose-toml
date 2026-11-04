// SPDX-License-Identifier: Apache-2.0
import toml from "../..";
import std;
import os;
import json;

extern fn consume(value: i64) -> i64 = "compare_consume";

fn visit(doc: toml::Document&, stats: i64[12]&) {
    // The same semantic nodes are visited as in the tree based competitors.
    // Goose stores them in a flat owned DOM; keys belong to table children.
    for node, id in doc.nodes {
        stats[0]++;
        if node.parent >= 0 && doc.nodes[node.parent].kind == toml::Kind.Table { stats[7] += toml::key(doc, id).len; }
        if node.kind == toml::Kind.Table { stats[1]++; }
        else if node.kind == toml::Kind.Array { stats[2]++; }
        else if node.kind == toml::Kind.String { stats[3]++; stats[8] += toml::text(doc, id).len; }
        else if node.kind == toml::Kind.Integer { stats[4]++; stats[9] += node.integer; }
        else if node.kind == toml::Kind.Float { stats[5]++; stats[10] += (node.number * 1000.0) as! i64; }
        else if node.kind == toml::Kind.Boolean { stats[6]++; if node.boolean { stats[11]++; } }
        else { abort("datetime is outside this corpus checksum schema"); }
    }
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
    else if node.kind == toml::Kind.Float { json::format_number(out, node.number); }
    else if node.kind == toml::Kind.Boolean { out.append(if node.boolean { "true" } else { "false" }); }
    else { abort("unexpected datetime"); }
}
fn step(source: u8[:], doc: toml::Document&, full: bool, total: i64[12]&) -> i64 {
    let error = toml::parse_into(source, doc);
    if error.len > 0 { write_stderr(error); exit(1); }
    let roots = consume(doc.nodes[0].count);
    if full {
        var stats: i64[12] = [0; 12]; visit(doc, stats);
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
    var total: i64[12] = [0; 12];
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
    for count, j in total { if j > 0 { out.push(','); } format(out, count); }
    out.append("]}"); print(out);
}
