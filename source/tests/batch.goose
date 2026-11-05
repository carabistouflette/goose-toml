// SPDX-License-Identifier: Apache-2.0
namespace batch_tests;
import toml from "../..";
import toml.source.editor;
import std;
fn request_put(path: const (const u8[:])[:], value: const u8[:]) -> toml_source::Edit {
    return toml_source::Edit.Put { path: path, value: value };
}
fn request_remove(path: const (const u8[:])[:]) -> toml_source::Edit {
    return toml_source::Edit.Remove { path: path };
}
fn expect(source: const u8[:], edits: const toml_source::Edit[:], expected: const u8[:], version: toml::Version = toml::Version.V1_0) {
    let output, error = toml_source::apply(source, edits, version);
    if error.len > 0 { print(error); }
    assert(error.len == 0 && output == expected);
}
fn reject(source: const u8[:], edits: const toml_source::Edit[:]) {
    let output, error = toml_source::apply(source, edits);
    assert(output.len == 0 && error.len > 0);
}
fn single(source: const u8[:], path: const u8[:][:], value: const u8[:]) {
    let put, put_error = toml_source::put(source, path, value);
    let batch, batch_error = toml_source::apply(source, [request_put(path, value)]);
    assert((put_error.len == 0) == (batch_error.len == 0) && put == batch);
    let removed, remove_error = toml_source::remove(source, path);
    let batch_removed, batch_remove_error = toml_source::apply(source, [request_remove(path)]);
    assert((remove_error.len == 0) == (batch_remove_error.len == 0) && removed == batch_removed);
}
fn limits() {
    let limit = 1048576;
    var names: u8[>..] = []; let digits = "0123456789abcdef";
    for i in 64 { names.push(digits[i >> 4]); names.push(digits[i & 15]); }
    var parts: (const u8[:])[>..] = [];
    for i in 64 { parts.push(names[i * 2..i * 2 + 2]); }
    var edits: toml_source::Edit[>..] = [];
    for i in 64 { edits.push(request_remove(parts[i..i + 1])); }
    expect("", edits, "");
    var created: toml_source::Edit[>..] = [];
    for i in 64 { created.push(request_put(parts[i..i + 1], "1")); }
    let full, full_error = toml_source::apply("", created);
    assert(full_error.len == 0);
    created[63] = request_put(parts[63..64], "[");
    let failed_last, last_error = toml_source::apply("", created);
    assert(failed_last.len == 0 && find(last_error, "batch edit 63:") >= 0);
    let cleared, clear_error = toml_source::apply(full, edits);
    assert(clear_error.len == 0 && cleared.len == 64);
    for byte in cleared { assert(byte == '\n'); }

    let overflow_path: (const u8[:])[1] = ["overflow"];
    edits.push(request_remove(overflow_path));
    let too_many, count_error = toml_source::apply("", edits);
    assert(too_many.len == 0 && count_error == "toml source: batch exceeds 64 edits");
    var value: u8[>..] = []; value.push(39);
    for i in limit - 6 { value.push('a'); }
    value.push(39);
    let exact, exact_error = toml_source::apply("x=1  ", [request_put(["x"], value)]);
    assert(exact_error.len == 0 && exact.len == limit && exact[..2] == "x=" &&
        exact[2..exact.len - 2] == value && exact[exact.len - 2..] == "  ");
    reject("x=1   ", [request_put(["x"], value)]);
    var dense: u8[>..] = []; dense.append("v=[");
    for i in 65534 { dense.append("1,"); }
    dense.push(']');
    let nodes, node_error = toml_source::apply(dense, [request_put(["new"], "1")]);
    assert(nodes.len == 0 && find(node_error, "node limit") >= 0);
    var oversized: u8[>..] = [];
    for i in limit + 1 { oversized.push(' '); }
    reject(oversized, []);
    // Exactly one MiB of decoded request bytes, mostly missing removal paths.
    var keys: u8[>..] = [];
    for i in 63 { for j in 4095 { keys.push('k'); } keys.push((i + 32) as u8); }
    var paths: (const u8[:])[>..] = [];
    for i in 63 { paths.push(keys[i * 4096..(i + 1) * 4096]); }
    let v_path: (const u8[:])[1] = ["v"];
    var raw: u8[>..] = []; raw.push(39);
    for i in limit - 63 * 4096 - 3 { raw.push('a'); }
    raw.push(39);
    var requests: toml_source::Edit[>..] = [];
    for i in 63 { requests.push(request_remove(paths[i..i + 1])); }
    requests.push(request_put(v_path, raw));
    let bytes, byte_error = toml_source::apply("", requests);
    assert(byte_error.len == 0 && bytes.len > raw.len);
    raw.push(' '); requests[63] = request_put(v_path, raw);
    let too_large, request_error = toml_source::apply("", requests);
    assert(too_large.len == 0 && request_error == "toml source: batch request exceeds 1 MiB");
}
fn run() {
    expect("# keep", [request_put(["c"], "1"),
        request_put(["a"], "2"), request_put(["b"], "3")],
        "\"c\" = 1\n\"a\" = 2\n\"b\" = 3\n# keep");
    expect("", [request_put(["new", "x"], "1"),
        request_put(["new", "y"], "2")], "\"new\".\"x\" = 1\n\"new\".\"y\" = 2\n");
    expect("a=1", [request_remove(["a"]), request_put(["b"], "2")], "\"b\" = 2\n");
    expect("[gone]\nx=1\n[keep]\ny=2", [request_remove(["gone"]),
        request_put(["new"], "3")], "\"new\" = 3\n\n\n[keep]\ny=2");
    let source = "# title\r\n[a] # hdr\r\nx=0x10 # x\r\ny=[1,\r\n# inside\r\n2]\r\n[z]\r\nkeep='stay'\r\n";
    expect(source, [request_put(["a", "x"], "0x20"),
        request_remove(["a", "y"]),
        request_put(["a", "new"], "{v='世界'}"),
        request_put(["other"], "true")],
        "\"other\" = true\r\n# title\r\n[a] # hdr\r\nx=0x20 # x\r\n\r\n\"new\" = {v='世界'}\r\n[z]\r\nkeep='stay'\r\n");
    expect("[a.b]\nx=1\n[z]\ny=2\n[a.c]\nx=3", [request_remove(["a"]),
        request_put(["z", "y"], "4")], "\n\n[z]\ny=4\n\n");
    expect("[[a]]\nx=1\n[[a]]\nx=2\nb=3", [request_remove(["a"])], "\n\n\n\n");
    reject("", [request_put(["a"], "1"), request_remove(["a"])]);
    reject("", [request_put(["a", "b"], "1"), request_remove(["a"])]);
    reject("[a]\nb=1", [request_remove(["a"]), request_put(["a", "c"], "2")]);
    reject("x=1", [request_put(["x"], "2"), request_put(["bad"], "[")]);
    reject("x=1", [request_put([], "1")]);
    reject("x=1", [request_remove(["\xff"])]);
    reject("a={x=1}\nb=2", [request_put(["b"], "3"), request_remove(["a", "x"])]);
    let _, fragment_error = toml_source::apply("a={x=1}", [request_remove(["a", "x"]), request_put(["bad"], "[")]);
    assert(find(fragment_error, "batch edit 1:") >= 0);
    let _, before_source = toml_source::apply("x=[", [request_put(["ok"], "[")]);
    assert(find(before_source, "batch edit 0:") >= 0);
    let _, before_fragment = toml_source::apply("x=[", [request_put(["a"], "["), request_remove(["a"])]);
    assert(before_fragment == "toml source: batch edit 1: overlapping batch paths");
    reject("x=[", []);
    reject("x=[", [request_remove(["missing"])]);
    expect("x=1 # keep", [], "x=1 # keep");
    expect("x=1 # keep", [request_remove(["missing"])], "x=1 # keep");
    expect("", [request_put(["v"], "{x=1,}")], "\"v\" = {x=1,}\n", toml::Version.V1_1);
    reject("", [request_put(["v"], "{x=1,}")]);
    for text in ["", "x=1", "x=1 # keep", "[a]\nx=1", "a.x=1", "a={x=1}", "[[a]]\nx=1", "x=["] {
        for name in ["x", "new", "a"] { single(text, [name], "[2,3]"); }
        single(text, ["a", "x"], "2");
    }
    var borrowed: u8[>..] = []; borrowed.append("x='borrowed'");
    let parts: (const u8[:])[1] = [borrowed[..1]];
    let out, err = toml_source::apply(borrowed, [request_put(parts, borrowed[2..])]);
    borrowed[0] = 'y'; assert(err.len == 0 && out == "x='borrowed'");
    var deep: (const u8[:])[>..] = []; for i in 64 { deep.push("x"); }
    let failed, retained = toml_source::apply("", [request_put(deep, "[1]")]);
    assert(failed.len == 0 && retained.len > 0);
    var saved: u8[>..] = []; saved.append(retained);
    expect("x=1", [request_put(["x"], "2")], "x=2");
    assert(retained == saved);
    reject("\xff", []);
    reject("x=1", [request_put(["x"], "\xff")]);
    limits();
    print("Atomic snapshot batch checks passed");
}
