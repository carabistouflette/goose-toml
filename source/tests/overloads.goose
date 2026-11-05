// SPDX-License-Identifier: Apache-2.0
import toml from "../..";
import toml.source.editor;
import std;
fn str(a: const u8[:]) -> u8[>..] { [] }
fn str(a: const u8[:], b: const u8[:], c: const u8[:], d: i64, e: const u8[:], f: i64, g: const u8[:], h: i64, i: const u8[:]) -> u8[>..] { [] }
fn copy(value: u8[>..]&) -> u8[>..] { [] }
fn copy(value: i64[>..]&) -> i64[>..] { [] }
fn parse_int(value: const u8[:]) -> i64, bool { return 999, true; }
fn parse_int(value: u8[>..]&, base: i64) -> i64, bool { return 998, true; }
fn parse_flt(value: u8[>..]&) -> f64, bool { return 997.0, true; }
fn format(output: u8[>..]&, value: i64) {}
fn main() {
    let x_path: (const u8[:])[1] = ["x"]; let y_path: (const u8[:])[1] = ["y"];
    let edits: toml_source::Edit[2] = [toml_source::Edit.Put { path: y_path, value: "2" },
        toml_source::Edit.Remove { path: x_path }];
    let batched, batch_error = toml_source::apply("x=1", edits);
    assert(batch_error.len == 0 && batched == "\"y\" = 2\n");
    let bad_edits: toml_source::Edit[1] = [toml_source::Edit.Put { path: x_path, value: "[" }];
    let batch_bad, batch_bad_error = toml_source::apply("x=1", bad_edits);
    assert(batch_bad.len == 0 && find(batch_bad_error, "batch edit 0:") >= 0);
    let inline_output, inline_error = toml_source::put("v={x=1,y={z=2}}", ["v", "y", "z"], "3");
    assert(inline_error.len == 0 && inline_output == "v={x=1,y={z=3}}");
    let legacy_bad, legacy_error = toml_source::legacy_set("x=1", ["x"], "[");
    assert(legacy_bad.len == 0 && legacy_error == "toml: invalid decimal integer part at byte 5 (line 1, byte column 6)");
    let legacy_ok, legacy_ok_error = toml_source::legacy_set("x=12", ["new"], "1.5");
    assert(legacy_ok_error.len == 0 && legacy_ok == "\"new\" = 1.5\nx=12");
    let legacy_remove, legacy_remove_error = toml_source::legacy_remove("x=1", ["x", "missing"]);
    assert(legacy_remove.len == 0 && legacy_remove_error == "toml-edit: cannot traverse an array, scalar or inline table");
    let malformed, malformed_error = toml_source::put("x=1", ["z"], "[1");
    assert(malformed_error.len > 0 && malformed.len == 0);
    let overflow, overflow_error = toml_source::put("x=1", ["z"], "9223372036854775808");
    assert(overflow_error.len > 0 && overflow.len == 0);
    let missing_path, missing_error = toml_source::put("", [], "1");
    assert(missing_error.len > 0 && missing_path.len == 0);
    let invalid_source, source_error = toml_source::remove("a=[", ["a"]);
    assert(source_error.len > 0 && invalid_source.len == 0);
    var source: u8[>..] = [];
    for i in 40 {
        source.push('x'); if i >= 10 { source.push('0' + (i / 10) as u8); }
        source.push('0' + (i % 10) as u8); source.append("=12\n");
    }
    let output, error = toml_source::put(source, ["new"], "1.5");
    assert(error.len == 0);
    var doc = toml::Document { .. };
    assert(toml::parse_into(output, doc).len == 0);
    assert(doc.nodes[toml::find(doc, 0, "x39")].integer == 12);
    assert(doc.nodes[toml::find(doc, 0, "new")].number == 1.5);
    print("Source-editor consumer overload checks passed");
}
