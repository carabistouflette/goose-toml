// SPDX-License-Identifier: Apache-2.0
import toml from "..";
import std;
fn only11(source: u8[:]) {
    var doc = toml::Document { .. };
    let error = toml::parse_into(source, doc, toml::Version.V1_1);
    if error.len > 0 { print(error); }
    assert(error.len == 0);
    assert(toml::parse_into(source, doc).len > 0);
}
fn bad11(source: u8[:]) {
    var doc = toml::Document { .. };
    assert(toml::parse_into(source, doc, toml::Version.V1_1).len > 0);
}
fn main() {
    only11("v={a=1,}"); only11("v={\n# note\na=1, # tail\nb={\nx=2,\n},\n}");
    only11("v={# empty\n}"); only11("v={a=1 # note\n,b=2}");
    only11("v=\"\\e\\x00\\x7f\\x80\\xff\"");
    only11("\"\\x61\"=\"\"\"\\e\"\"\"");
    for time in ["07:32", "00:00", "23:59", "1979-05-27T07:32", "1979-05-27 07:32Z",
            "1979-05-27t07:32z", "1979-05-27T07:32+07:00", "1979-05-27T07:32-23:59"] {
        let source = str("v=", time); only11(source);
    }
    var doc = toml::Document { .. };
    assert(toml::parse_into("v=\"\\e\\x00\\x7f\\x80\\xff\"", doc, toml::Version.V1_1).len == 0);
    let id = toml::find(doc, 0, "v");
    assert(toml::text(doc, id) == "\x1b\0\x7f\xc2\x80\xc3\xbf");
    assert(toml::parse_into("v=07:32", doc, toml::Version.V1_1).len == 0);
    assert(doc.nodes[toml::find(doc, 0, "v")].kind == toml::Kind.LocalTime);
    assert(toml::text(doc, toml::find(doc, 0, "v")) == "07:32");
    assert(toml::parse_into("v='\\e\\x61'", doc).len == 0);
    assert(toml::text(doc, toml::find(doc, 0, "v")) == "\\e\\x61");
    for source in ["v=24:00", "v=07:60", "v=07:32.5", "v=07:32:", "v=07:32Z", "v=07:32+07:00",
            "v=1979-05-27T07:32+24:00", "v=1979-05-27T07:32.5Z", "v={a=1,,}",
            "v={a=1\nb=2}", "v={,}", "v={a=1# no closing brace}", "v=\"\\x0\"", "v=\"\\xgg\""] { bad11(source); }
    assert(toml::parse_into("a=1\n\"\\x61\"=2", doc, toml::Version.V1_1).len > 0);
    print("TOML version-specific grammar tests passed");
}
