// SPDX-License-Identifier: Apache-2.0
import toml from "..";
import std;

fn accepted(source: u8[:]) {
    var doc = toml::Document { .. };
    let error = toml::parse_into(source, doc);
    if error.len > 0 { print("unexpected rejection: ", source, "\n", error); }
    assert(error.len == 0 && doc.nodes.len >= 1 && doc.nodes[0].kind == toml::Kind.Table);
}
fn rejected(source: u8[:]) {
    var doc = toml::Document { .. };
    let error = toml::parse_into(source, doc);
    if error.len == 0 { print("unexpected acceptance: ", source); }
    assert(error.len > 0);
}
fn integer(source: u8[:], expected: i64) {
    var doc = toml::Document { .. };
    let error = toml::parse_into(source, doc);
    if error.len > 0 { print(error); }
    assert(error.len == 0);
    let id = toml::find(doc, 0, "v");
    assert(id >= 0 && doc.nodes[id].kind == toml::Kind.Integer && doc.nodes[id].integer == expected);
}
fn floating(source: u8[:], expected: f64) {
    var doc = toml::Document { .. };
    let error = toml::parse_into(source, doc);
    if error.len > 0 { print(error); }
    assert(error.len == 0);
    let id = toml::find(doc, 0, "v");
    assert(id >= 0 && doc.nodes[id].kind == toml::Kind.Float && doc.nodes[id].number == expected);
}
fn string_value(source: u8[:], expected: u8[:]) {
    var doc = toml::Document { .. };
    let error = toml::parse_into(source, doc);
    if error.len > 0 { print(error); }
    assert(error.len == 0);
    let id = toml::find(doc, 0, "v");
    assert(id >= 0 && doc.nodes[id].kind == toml::Kind.String && toml::text(doc, id) == expected);
}
fn date_value(source: u8[:], expected: u8[:], kind: toml::Kind) {
    var doc = toml::Document { .. };
    let error = toml::parse_into(source, doc);
    if error.len > 0 { print(error); }
    assert(error.len == 0);
    let id = toml::find(doc, 0, "v");
    assert(id >= 0 && doc.nodes[id].kind == kind && toml::text(doc, id) == expected);
}
fn ownership_source(doc: toml::Document&) {
    var source = str("'own.key' = \"Goose\\n\\U0001F600\"\ndate = 2000-02-29\n");
    assert(toml::parse_into(source, doc).len == 0);
    source.clear();
    source.append("overwritten input allocation");
}
fn syntax_tests() {
    accepted(""); accepted(" \t\n# comment\r\n"); accepted("# no final newline");
    integer("v=+99", 99); integer("v=-0", 0); integer("v=+0", 0);
    integer("v=-9223372036854775808", -9223372036854775808);
    integer("v=9223372036854775807", 9223372036854775807);
    integer("v=0x7fff_ffff_ffff_ffff", 9223372036854775807);
    integer("v=0xDEAD_beef", 3735928559); integer("v=0o0755", 493); integer("v=0b1101_0010", 210);
    integer("v=1_2_345", 12345);
    floating("v=+1.25", 1.25); floating("v=1_2.3_4e+0_2", 1234.0); floating("v=-2E-2", -0.02);
    // A negative exponent sign at byte four is not a date separator.
    floating("v=1.0e-2", 0.01); floating("v=123e-2", 1.23);
    floating("v=+12e-2", 0.12); floating("v=-12e-2", -0.12);
    floating("v=1.0E-2", 0.01);
    floating("v=1e-9999", 0.0); floating("v=1.7976931348623157e308", 1.7976931348623157e308);
    floating("v=5e-324", 5e-324);
    floating("v=inf", 1.0 / 0.0); floating("v=+inf", 1.0 / 0.0); floating("v=-inf", -1.0 / 0.0);
    var special = toml::Document { .. };
    assert(toml::parse_into("a=nan\nb=+nan\nc=-nan\nz=-0.0", special).len == 0);
    for name in ["a", "b", "c"] {
        let n = special.nodes[toml::find(special, 0, name)].number;
        assert(n != n);
    }
    assert(1.0 / special.nodes[toml::find(special, 0, "z")].number < 0.0);

    string_value("v=\"\"", ""); string_value("v=''", "");
    string_value("v='C:\\Users\\goose'", "C:\\Users\\goose");
    string_value("v=\"é😀\\t\\n\\r\\b\\f\\\"\\\\\"", "é😀\t\n\r\x08\x0c\"\\");
    string_value("v=\"\\u0000\\u007f\\u00E9\\U0001F600\"", "\0\x7fé😀");
    string_value("v=\"\"\"\nfirst\r\nsecond\"\"\"", "first\nsecond");
    string_value("v='''\r\nfirst\nsecond'''", "first\nsecond");
    string_value("v=\"\"\"a\\ \t\r\n \n\tb\"\"\"", "ab");
    string_value("v=\"\"\"a\"\"\"\"", "a\"");
    string_value("v=\"\"\"a\"\"\"\"\"", "a\"\"");
    string_value("v='''a''''", "a'"); string_value("v='''a'''''", "a''");
    string_value("v=\"\"\"a\"\"b\"\"\"", "a\"\"b");
    date_value("v=2016-12-31T23:59:60Z", "2016-12-31T23:59:60Z", toml::Kind.OffsetDateTime);
    date_value("v=2000-02-29", "2000-02-29", toml::Kind.LocalDate);
    date_value("v=0000-01-01", "0000-01-01", toml::Kind.LocalDate);
    date_value("v=07:32:00.123456789123", "07:32:00.123456789123", toml::Kind.LocalTime);
    date_value("v=1979-05-27t07:32:00z", "1979-05-27t07:32:00z", toml::Kind.OffsetDateTime);
    date_value("v=1979-05-27 07:32:00-07:00", "1979-05-27 07:32:00-07:00", toml::Kind.OffsetDateTime);
    date_value("v=1979-05-27T07:32:00", "1979-05-27T07:32:00", toml::Kind.LocalDateTime);

    var doc = toml::Document { .. };
    assert(toml::parse_into("''=1\n\"a.b\"=2\na.b=3\n'日本語'=true\nfalse=false\n", doc).len == 0);
    assert(doc.nodes[toml::find(doc, 0, "")].integer == 1);
    assert(doc.nodes[toml::find(doc, 0, "a.b")].integer == 2);
    let a = toml::find(doc, 0, "a");
    assert(doc.nodes[toml::find(doc, a, "b")].integer == 3);
    assert(doc.nodes[toml::find(doc, 0, "日本語")].boolean);
    assert(!doc.nodes[toml::find(doc, 0, "false")].boolean);
    assert(toml::find(doc, -1, "x") == -1 && toml::find(doc, doc.nodes.len, "x") == -1);
    assert(toml::find(doc, toml::find(doc, 0, "a.b"), "x") == -1);
    assert(toml::find(doc, 0, "missing") == -1);
    assert(toml::parse_into("v=[1,true,'x',[2],{a.b=3},]\nempty=[]\ninline={}\n", doc).len == 0);
    let array = toml::find(doc, 0, "v");
    assert(doc.nodes[array].kind == toml::Kind.Array && doc.nodes[array].count == 5);
    let first = doc.nodes[array].first;
    let second = doc.nodes[first].next;
    assert(doc.nodes[first].integer == 1 && doc.nodes[second].boolean);
    assert(doc.nodes[doc.nodes[array].last].kind == toml::Kind.Table);
    assert(doc.nodes[toml::find(doc, 0, "empty")].count == 0);
    accepted("v=[\n# a\n1\n, # b\n2,\n]\n");
    accepted("v={a=[\n1,\n2\n],b=\"\"\"\nhello\n\"\"\"}\n");
}
fn table_tests() {
    accepted("[a.b.c]\n[a]\nb.d=1\n");
    accepted("a.b=1\n[a.c]\nx=2\n");
    accepted("a.b.c=1\n[a.b.d]\nx=2\n");
    accepted("[a.b]\n[a]\n[a.c]\n");
    rejected("[a.b.c]\n[a]\nb.d=1\n[a.b]\n");
    rejected("a.b.c=1\n[a]\n");
    rejected("[a.b]\nx=1\n[a]\nb.c=2\n");
    rejected("a={b.c=1}\na.b.d=2\n");
    rejected("a={b.c=1}\n[a.b.d]\n");
    rejected("a=[{x=1}]\n[[a]]\n");
    rejected("a=[{x=1}]\n[a.y]\n");
    rejected("a=[]\n[[a]]\n");
    rejected("[a]\n[a]\n");
    rejected("a=1\na.b=2\n");
    rejected("a.b=1\na=2\n");
    rejected("a={x=1}\na.y=2\n");
    rejected("[[a]]\n[a]\n");
    rejected("[a]\n[[a]]\n");
    rejected("v={a=1,a=2}");
    rejected("a=1\n\"\\u0061\"=2");
    rejected("''=1\n\"\"=2");
    var doc = toml::Document { .. };
    assert(toml::parse_into("[[fruit]]\nname='apple'\n[fruit.physical]\ncolor='red'\n[[fruit.variety]]\nname='red delicious'\n[[fruit]]\nname='banana'\n[fruit.physical]\ncolor='yellow'\n", doc).len == 0);
    let fruit = toml::find(doc, 0, "fruit");
    assert(doc.nodes[fruit].count == 2 && doc.nodes[fruit].kind == toml::Kind.Array);
    let apple = doc.nodes[fruit].first;
    let banana = doc.nodes[fruit].last;
    assert(toml::text(doc, toml::find(doc, apple, "name")) == "apple");
    assert(toml::text(doc, toml::find(doc, banana, "name")) == "banana");
    let physical = toml::find(doc, banana, "physical");
    assert(toml::text(doc, toml::find(doc, physical, "color")) == "yellow");
    assert(toml::find(doc, banana, "variety") == -1);
}
fn malformed_tests() {
    for source in ["v=", "v=\n", "v=+", "v=-", "v=null", "v=True", "v=FALSE", "v=Inf", "v=NaN",
            "v=01", "v=+01", "v=-01", "v=0_1", "v=+0x1", "v=-0x1", "v=0x", "v=0b2", "v=0o8", "v=0X1", "v=0x-1", "v=0x+1", "v=0o-1", "v=0b+1",
            "v=_1", "v=1_", "v=1__0", "v=0x_1", "v=0x1_", "v=1_.0", "v=1._0", "v=1e_2", "v=1_e2",
            "v=.1", "v=1.", "v=1.e2", "v=1e", "v=1e+", "v=1e-", "v=--1", "v=1.2.3", "v=00.1",
            "v=9223372036854775808", "v=-9223372036854775809", "v=0x8000000000000000", "v=1e9999",
            "v=1900-02-29", "v=2000-02-30", "v=2000-00-01", "v=2000-13-01", "v=2000-01-00", "v=2000-04-31",
            "v=24:00:00", "v=00:60:00", "v=00:00:61", "v=07:32", "v=07:32:00.", "v=7:32:00", "v=07:32:00Z",
            "v=1979-05-27T07:32:00+24:00", "v=1979-05-27T07:32:00+00:60", "v=1979-05-27T07:32:00+0000",
            "v=1979-05-27  07:32:00", "v=1979-05-27\t07:32:00", "v=1979-05-27T07:32:00zZ",
            "v='unterminated", "v=\"unterminated", "v=\"a\nb\"", "v='a\nb'", "v=\"\\q\"", "v=\"\\x41\"",
            "v=\"\\uD800\"", "v=\"\\uDC00\"", "v=\"\\U00110000\"", "v=\"\\u123\"", "v=\"\\uGGGG\"",
            "v=\"\"\"a\\ b\"\"\"", "v=\"\"\"a\"\"\"\"\"\"", "v='''a''''''", "v=\"\"\"unterminated",
            "v=[", "v=[1", "v=[1 2]", "v=[,]", "v=[1,,2]", "v={", "v={a=1,}", "v={a=1\nb=2}", "v={a=1,#x\nb=2}",
            "[]", "[[]]", "[a", "[a]x", "[[a]", "[a]]", "a..b=1", ".a=1", "a.=1", "=1", "a b=1", "é=1",
            "\"\"\"a\"\"\"=1", "v=1 v=2", "v=1\r", "# x\r", "v='a\rb'", "v=\"\"\"a\rb\"\"\""] { rejected(source); }
    // Reject raw controls everywhere while permitting them when escaped in basic strings.
    for control in [0, 1, 8, 11, 12, 31, 127] {
        var source = str("v='a"); source.push(control as u8); source.append("b'"); rejected(source);
        source.clear(); source.append("# a"); source.push(control as u8); rejected(source);
    }
    for bytes in [[0xc0, 0x80, 0, 0], [0xed, 0xa0, 0x80, 0], [0xf4, 0x90, 0x80, 0x80], [0xe2, 0x82, 0, 0], [0xff, 0, 0, 0]] {
        var source = str("v='");
        for c in bytes { if c != 0 { source.push(c as u8); } }
        source.push('\''); rejected(source);
    }
    // Any prefix that ends within the value cannot complete this assignment.
    let complete = "v=\"hello\\u00E9\"";
    for i in 2..complete.len { rejected(complete[..i]); }
}
fn ownership_and_index_tests() {
    var doc = toml::Document { .. };
    ownership_source(doc);
    let name = toml::find(doc, 0, "own.key");
    assert(toml::key(doc, name) == "own.key" && toml::text(doc, name) == "Goose\n😀");
    assert(toml::text(doc, toml::find(doc, 0, "date")) == "2000-02-29");
    assert(toml::parse_into("replacement=2", doc).len == 0);
    assert(toml::find(doc, 0, "own.key") == -1 && doc.nodes[toml::find(doc, 0, "replacement")].integer == 2);
    assert(toml::parse_into("broken=", doc).len > 0);
    assert(toml::parse_into("", doc).len == 0 && doc.nodes.len == 1 && doc.nodes[0].count == 0);
    var wide: u8[>..] = [];
    for i in 3000 { wide.append(str("key", i, "=", i, "\n")); }
    assert(toml::parse_into(wide, doc).len == 0 && doc.nodes[0].count == 3000);
    for i in 3000 {
        let name = str("key", i);
        let id = toml::find(doc, 0, name);
        assert(id >= 0 && doc.nodes[id].integer == i);
    }
}
fn limit_tests() {
    var large: u8[>..] = [];
    for i in toml::MAX_INPUT_BYTES { large.push(' '); }
    accepted(large); large.push(' '); rejected(large);
    var number = str("v=1.");
    for i in toml::MAX_NUMBER_BYTES - 2 { number.push('0'); }
    floating(number, 1.0); number.push('0'); rejected(number);
    var nested = str("v=");
    for i in toml::MAX_DEPTH - 1 { nested.push('['); }
    nested.push('1');
    for i in toml::MAX_DEPTH - 1 { nested.push(']'); }
    accepted(nested);
    nested.clear(); nested.append("v=");
    for i in toml::MAX_DEPTH { nested.push('['); }
    nested.push('1');
    for i in toml::MAX_DEPTH { nested.push(']'); }
    rejected(nested);
    var dotted: u8[>..] = [];
    for i in toml::MAX_DEPTH { if i > 0 { dotted.push('.'); } dotted.push('a'); }
    dotted.append("=1"); accepted(dotted);
    dotted.clear();
    for i in toml::MAX_DEPTH + 1 { if i > 0 { dotted.push('.'); } dotted.push('a'); }
    dotted.append("=1"); rejected(dotted);
    // Combining a dotted parent and an array must respect the same logical tree limit.
    dotted.clear();
    for i in toml::MAX_DEPTH { if i > 0 { dotted.push('.'); } dotted.push('a'); }
    dotted.append("=[1]"); rejected(dotted);
    var nodes = str("v=[");
    for i in toml::MAX_NODES - 2 { if i > 0 { nodes.push(','); } nodes.push('1'); }
    nodes.push(']'); accepted(nodes);
    nodes.pop(); nodes.append(",1]"); rejected(nodes);
}
fn main() {
    syntax_tests(); table_tests(); malformed_tests(); ownership_and_index_tests(); limit_tests();
    print("parser tests passed");
}
