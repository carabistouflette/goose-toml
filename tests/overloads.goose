// SPDX-License-Identifier: Apache-2.0
// Regression at the consumer boundary: global convenience overloads must not
// erase validation failures, alter numeric conversion or corrupt index growth.
import toml from "..";
import std;
fn str(a: const u8[:]) -> u8[>..] { [] }
fn str(value: f64) -> u8[>..] { [] }
fn str(value: i64) -> u8[>..] { [] }
fn format(out: u8[>..]&, value: i64) {}
fn format(out: u8[>..]&, value: f64) {}
fn format(out: u8[..32]&, value: f64) {}
fn str(a: const u8[:], b: const u8[:], c: const u8[:], d: i64,
       e: const u8[:], f: i64, g: const u8[:], h: i64, i: const u8[:]) -> u8[>..] { [] }
fn copy(value: u8[>..]&) -> u8[>..] { [] }
fn copy(value: i64[>..]&) -> i64[>..] { [] }
fn parse_int(value: const u8[:]) -> i64, bool { return 123, true; }
fn parse_int(value: u8[>..]&, base: i64) -> i64, bool { return 2, true; }
fn parse_flt(value: u8[>..]&) -> f64, bool { return 2.0, true; }
fn max(a: i64, b: i64) -> i64 { 16 }
fn rejected(text: const u8[:]) {
    var doc = toml::Document { .. };
    assert(toml::parse_into(text, doc).len > 0);
}
fn main() {
    var doc = toml::Document { .. };
    assert(toml::parse_into("v=[1", doc) == "toml: unexpected delimiter at byte 4 (line 1, byte column 5)");
    for text in ["v=01", "v=", "v=9223372036854775808", "v=1e99999", "v=1.", "v=0x8000000000000000"] {
        rejected(text);
    }
    assert(toml::parse_into("i=41\nf=1.25\nx=0x2a", doc).len == 0);
    assert(doc.nodes[toml::find(doc, 0, "i")].integer == 41);
    assert(doc.nodes[toml::find(doc, 0, "f")].number == 1.25);
    assert(doc.nodes[toml::find(doc, 0, "x")].integer == 42);
    assert(toml::parse_into("i=-9223372036854775808\nf=1e300\nsmall=1e-9\nfast=0.125\nzero=-0.0", doc).len == 0);
    let numbers, number_error = toml::serialize(doc); assert(number_error.len == 0 && numbers.len > 0);
    var back = toml::Document { .. }; assert(toml::parse_into(numbers, back).len == 0);
    assert(back.nodes[toml::find(back, 0, "i")].integer == -9223372036854775808);
    assert(back.nodes[toml::find(back, 0, "f")].number == 1e300);
    assert(back.nodes[toml::find(back, 0, "small")].number == 1e-9);
    assert(back.nodes[toml::find(back, 0, "fast")].number == 0.125);
    assert(float_text::bits_of(back.nodes[toml::find(back, 0, "zero")].number) == float_text::bits_of(-0.0));
    var invalid: u8[>..] = []; invalid.push(255);
    assert(toml::parse_into(invalid, doc).len > 0);
    var large: u8[>..] = []; for i in toml::MAX_INPUT_BYTES + 1 { large.push(' '); }
    assert(toml::parse_into(large, doc).len > 0);
    let keys = ["k0", "k1", "k2", "k3", "k4", "k5", "k6", "k7", "k8", "k9",
                "k10", "k11", "k12", "k13", "k14", "k15", "k16", "k17", "k18", "k19"];
    var wide: u8[>..] = [];
    for key in keys { wide.append(key); wide.append("=1\n"); }
    assert(toml::parse_into(wide, doc).len == 0);
    for key in keys { assert(toml::find(doc, 0, key) > 0); }
    let output, error = toml::serialize(doc); assert(error.len == 0 && output.len > 0);
    assert(toml::parse_into(output, doc).len == 0);
    wide.append("k0=2\n"); assert(toml::parse_into(wide, doc).len > 0);
    toml::init(doc);
    let bad, put_error = toml::put(doc, -1, "x", toml::Input.Table); assert(bad == -1 && put_error.len > 0);
    assert(toml::set(doc, 0, toml::Input.Integer { value: 1 }).len > 0);
    doc.nodes[0].kind = toml::Kind.Array;
    let empty, write_error = toml::serialize(doc); assert(empty.len == 0 && write_error.len > 0);
    print("consumer overload regression tests passed");
}
