// SPDX-License-Identifier: Apache-2.0
import toml from "..";
import std;
import binary;

recursive fn same(a: toml::Document&, ai: i64, b: toml::Document&, bi: i64) {
    let x = a.nodes[ai]; let y = b.nodes[bi];
    assert(x.kind == y.kind && x.count == y.count);
    if x.kind == toml::Kind.Table {
        var child = x.first;
        while child >= 0 {
            let corresponding = toml::find(b, bi, toml::key(a, child)); assert(corresponding >= 0);
            same(a, child, b, corresponding); child = a.nodes[child].next;
        }
    } else if x.kind == toml::Kind.Array {
        var ac = x.first; var bc = y.first;
        while ac >= 0 { assert(bc >= 0); same(a, ac, b, bc); ac = a.nodes[ac].next; bc = b.nodes[bc].next; }
        assert(bc == -1);
    } else if x.kind == toml::Kind.Integer { assert(x.integer == y.integer); }
    else if x.kind == toml::Kind.Float {
        if x.number != x.number { assert(y.number != y.number); }
        else { assert(float_text::bits_of(x.number) == float_text::bits_of(y.number)); }
    } else if x.kind == toml::Kind.Boolean { assert(x.boolean == y.boolean); }
    else { assert(toml::text(a, ai) == toml::text(b, bi)); }
}
fn roundtrip(source: const u8[:]) {
    var doc = toml::Document { .. }; assert(toml::parse_into(source, doc).len == 0);
    let nodes = doc.nodes.len; let bytes = doc.bytes.len; let indexed = doc.indexed;
    let output, error = toml::serialize(doc);
    if error.len > 0 { print(error); }
    assert(error.len == 0 && doc.nodes.len == nodes && doc.bytes.len == bytes && doc.indexed == indexed);
    var back = toml::Document { .. };
    let parse_error = toml::parse_into(output, back);
    if parse_error.len > 0 { print(output, "\n", parse_error); }
    assert(parse_error.len == 0); same(doc, 0, back, 0);
    let again, again_error = toml::serialize(back); assert(again_error.len == 0 && again == output);
}
fn scalars_and_containers() {
    roundtrip(""); roundtrip("# empty\n[empty]\n[[also_empty]]\n");
    roundtrip("i=-9223372036854775808\nu=9223372036854775807\nt=true\nf=false\ns='é😀'\nempty=''\n''=''\n'quoted.key'='value'");
    roundtrip("z=0.0\nnz=-0.0\none=1.0\nsmall=5e-324\nmax=1.7976931348623157e308\nprecise=1.0000000000000002\nneg=-2.2250738585072014e-308\ne=1e20\ninf=inf\nninf=-inf\nnan=nan");
    roundtrip("d=2024-02-29\nt=07:32:00.123456789123456789\nl=1979-05-27 07:32:00\no=1979-05-27t07:32:00.1z\nzone=1979-05-27T07:32:00-07:00\nleap=2016-12-31T23:59:60Z");
    roundtrip("[service]\nname='goose'\nvalues=[1, 'two', true, {nested=[1.5, 2.5]}]\n[service.empty]\n[[workers]]\nname='first'\n[workers.details]\na=1\n[[workers]]\nname='second'\n[[workers.children]]\nvalue=2");
    roundtrip("a.b.c=1\na.b.d={x={y=[]}}\nq=[[[[[]]]]]");
    var doc = toml::Document { .. }; toml::init(doc);
    var controls: u8[>..] = []; for c in 32 { controls.push(c as u8); } controls.push(127); controls.append("\"\\🪿");
    let id, put_error = toml::put(doc, 0, controls, toml::Input.String { value: controls }); assert(id > 0 && put_error.len == 0);
    let output, error = toml::serialize(doc); assert(error.len == 0);
    for c in output { assert(c >= 32 && c != 127 || c == '\n'); }
    var back = toml::Document { .. }; assert(toml::parse_into(output, back).len == 0); same(doc, 0, back, 0);
    let signed_nan, nan_error = toml::put(doc, 0, "nan", toml::Input.Float { value: -0.0 / 0.0 }); assert(signed_nan > 0 && nan_error.len == 0);
    let nan_out, no_error = toml::serialize(doc); assert(no_error.len == 0 && nan_out.len > 0);
    // Reach the maximum supported nesting depth without a large fixture.
    toml::init(doc); var parent = 0;
    for i in 64 { let child, child_error = toml::put(doc, parent, "x", toml::Input.Table); assert(child_error.len == 0); parent = child; }
    let deep, deep_error = toml::serialize(doc); assert(deep_error.len == 0);
    assert(toml::parse_into(deep, back).len == 0); same(doc, 0, back, 0);
}
fn version_conversion() {
    var doc = toml::Document { .. };
    assert(toml::parse_into("s=\"\\e\\xFF\"\na={\nb=1,\n}\nt=07:32\nl=1979-05-27T07:32\no=1979-05-27T07:32-07:00\nz=1979-05-27t07:32z", doc, toml::Version.V1_1).len == 0);
    let output, error = toml::serialize(doc); assert(error.len == 0);
    var back = toml::Document { .. }; assert(toml::parse_into(output, back).len == 0);
    assert(toml::text(back, toml::find(back, 0, "t")) == "07:32:00");
    assert(toml::text(back, toml::find(back, 0, "l")) == "1979-05-27T07:32:00");
    assert(toml::text(back, toml::find(back, 0, "o")) == "1979-05-27T07:32:00-07:00");
    assert(toml::text(back, toml::find(back, 0, "z")) == "1979-05-27t07:32:00z");
    assert(toml::text(back, toml::find(back, 0, "s")) == "\x1bÿ");
    assert(toml::text(doc, toml::find(doc, 0, "t")) == "07:32");
    // The existing scalar token cap still applies with semantic construction.
    var long_time = str("07:32:00."); for i in 119 { long_time.push('1'); }
    let time_id, time_error = toml::put(doc, 0, "precision", toml::Input.DateTime { kind: toml::Kind.LocalTime, value: long_time });
    assert(time_id > 0 && time_error.len == 0);
    let precise, precise_error = toml::serialize(doc); assert(precise_error.len == 0 && toml::parse_into(precise, back).len == 0);
    assert(toml::text(back, toml::find(back, 0, "precision")) == long_time);
    long_time.push('1');
    let too_long, too_long_error = toml::put(doc, 0, "precision", toml::Input.DateTime { kind: toml::Kind.LocalTime, value: long_time });
    assert(too_long == -1 && too_long_error.len > 0);
}
fn random_float_roundtrips() {
    var random = rng { s: 20261104 };
    var doc = toml::Document { .. }; var back = toml::Document { .. };
    for i in 2000 {
        let bits: u64[1] = [rand_u64(random)];
        let number, read_ok = binary::read_f64le(bytes_of(bits), 0); assert(read_ok);
        toml::init(doc);
        let id, error = toml::put(doc, 0, "v", toml::Input.Float { value: number }); assert(id > 0 && error.len == 0);
        let output, write_error = toml::serialize(doc); assert(write_error.len == 0);
        assert(toml::parse_into(output, back).len == 0);
        let returned = back.nodes[toml::find(back, 0, "v")].number;
        if number != number { assert(returned != returned); }
        else { assert(float_text::bits_of(number) == float_text::bits_of(returned)); }
    }
}
fn rejected(doc: toml::Document&) {
    let output, error = toml::serialize(doc); assert(output.len == 0 && error.len > 0);
}
fn malformed() {
    var doc = toml::Document { .. }; rejected(doc);
    toml::init(doc); doc.nodes[0].kind = toml::Kind.Array; rejected(doc);
    toml::init(doc); doc.nodes[0].parent = 0; rejected(doc);
    toml::init(doc); doc.nodes[0].next = 0; rejected(doc);
    toml::init(doc); doc.nodes[0].first = 999; rejected(doc);
    assert(toml::parse_into("a=1", doc).len == 0); doc.nodes[0].count = 2; rejected(doc);
    assert(toml::parse_into("a=1", doc).len == 0); doc.nodes[0].last = -1; rejected(doc);
    assert(toml::parse_into("a=1", doc).len == 0); doc.nodes[1].next = 1; rejected(doc);
    assert(toml::parse_into("a=1", doc).len == 0); doc.nodes[1].parent = -2; rejected(doc);
    assert(toml::parse_into("a=1", doc).len == 0); doc.nodes[1].depth = 65; rejected(doc);
    assert(toml::parse_into("a=1", doc).len == 0); doc.nodes[1].first = 1; rejected(doc);
    assert(toml::parse_into("a='x'", doc).len == 0); doc.nodes[1].text.start = -1; rejected(doc);
    assert(toml::parse_into("a='x'", doc).len == 0); doc.nodes[1].text.len = 9223372036854775807; rejected(doc);
    assert(toml::parse_into("a='x'", doc).len == 0); doc.nodes[1].key.start = 9223372036854775807; rejected(doc);
    assert(toml::parse_into("a='x'", doc).len == 0); doc.bytes[1] = 255; rejected(doc);
    assert(toml::parse_into("a='x'", doc).len == 0); doc.bytes[0] = 255; rejected(doc);
    assert(toml::parse_into("a=1\nb=2", doc).len == 0); doc.nodes[2].key = doc.nodes[1].key; rejected(doc);
    assert(toml::parse_into("a=2024-02-29", doc).len == 0); doc.bytes[doc.nodes[1].text.start + 3] = '3'; rejected(doc);
    assert(toml::parse_into("a='2024-02-29'", doc).len == 0); doc.nodes[1].kind = toml::Kind.LocalTime; rejected(doc);
    // Overlapping forged spans are charged before UTF-8 or escaping work.
    toml::init(doc);
    for i in 10 { let id, error = toml::put(doc, 0, str(i), toml::Input.String { value: "" }); assert(error.len == 0); }
    let start = doc.bytes.len; for i in 1048500 { doc.bytes.push('x'); }
    for i in 1..doc.nodes.len { doc.nodes[i].text = toml::Span { start: start, len: 1048500 }; }
    rejected(doc);
    // Private unreachable retired storage is ignored semantically.
    assert(toml::parse_into("a={b='value'}", doc).len == 0);
    let removed, remove_error = toml::remove(doc, 0, "a"); assert(removed && remove_error.len == 0);
    doc.nodes[2].text.start = -99;
    let empty, empty_error = toml::serialize(doc); assert(empty_error.len == 0 && empty.len == 0);
}
fn compact_limit() {
    var doc = toml::Document { .. }; toml::init(doc);
    var value: u8[>..] = []; for i in 200000 { value.push(0); }
    let id, error = toml::put(doc, 0, "value", toml::Input.String { value: value }); assert(error.len == 0);
    let output, write_error = toml::serialize(doc); assert(write_error.len == 0 && output.len > 1048576);
    let nodes = doc.nodes.len; let bytes = doc.bytes.len;
    assert(toml::compact(doc).len > 0);
    assert(doc.nodes.len == nodes && doc.bytes.len == bytes && toml::text(doc, id) == value);
}
fn main() {
    scalars_and_containers(); version_conversion(); random_float_roundtrips(); malformed(); compact_limit();
    print("toml writer tests passed");
}
