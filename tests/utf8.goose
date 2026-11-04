// SPDX-License-Identifier: Apache-2.0
import toml from "..";
import std;
fn main() {
    for source in ["", "ASCII\0", "é世界😀", "\xef\xbb\xbf", "\xf4\x8f\xbf\xbf"] {
        assert(toml::valid_utf8(source));
    }
    for malformed in ["\x80", "\xc0\x80", "\xed\xa0\x80", "\xf4\x90\x80\x80", "\xf0\x90\x80", "\xff"] {
        var doc = toml::Document { .. };
        assert(!toml::valid_utf8(malformed));
        var input = str("value = '"); input.append(malformed); input.push('\'');
        assert(toml::parse_into(input, doc) == "toml: invalid UTF-8 at byte 0");
        assert(doc.nodes.len == 0 && doc.bytes.len == 0 && doc.index.len == 0);
        assert(toml::parse_into("value='valid'", doc).len == 0);
        assert(toml::text(doc, toml::find(doc, 0, "value")) == "valid");
    }
    var doc = toml::Document { .. };
    assert(toml::parse_into("value = \"é世😀\"", doc).len == 0);
    assert(toml::text(doc, toml::find(doc, 0, "value")) == "é世😀");
    // Strict scalar escapes retain the existing parser's accepted boundaries.
    assert(toml::parse_into("value = \"\\u0000\\u007f\\u0080\\u07ff\\u0800\\ud7ff\\ue000\\uffff\\U00010000\\U0010ffff\"", doc).len == 0);
    var value: u8[>..] = [];
    value.append(toml::text(doc, toml::find(doc, 0, "value")));
    assert(toml::valid_utf8(value));
    assert(value == "\0\x7f\xc2\x80\xdf\xbf\xe0\xa0\x80\xed\x9f\xbf\xee\x80\x80\xef\xbf\xbf\xf0\x90\x80\x80\xf4\x8f\xbf\xbf");
    for source in ["value=\"\\ud800\"", "value=\"\\udfff\"", "value=\"\\U00110000\""] {
        var rejected_doc = toml::Document { .. };
        assert(toml::parse_into(source, rejected_doc).len > 0);
    }
    print("TOML shared UTF-8 integration passed");
}
