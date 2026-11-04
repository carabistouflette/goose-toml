// SPDX-License-Identifier: Apache-2.0
import toml from "../..";
import toml.source.editor;
import std;
import compatibility;
fn put(source: const u8[:], path: const u8[:][:], value: const u8[:], expected: const u8[:], version: toml::Version = toml::Version.V1_0) {
    let output, error = toml_source::put(source, path, value, version);
    if error.len > 0 { print(error); }
    assert(error.len == 0 && output == expected);
}
fn remove(source: const u8[:], path: const u8[:][:], expected: const u8[:]) {
    let output, error = toml_source::remove(source, path);
    if error.len > 0 { print(error); }
    assert(error.len == 0 && output == expected);
}
fn reject(source: const u8[:], path: const u8[:][:], value: const u8[:]) {
    let output, error = toml_source::put(source, path, value);
    assert(error.len > 0 && output.len == 0);
}
fn main() {
    compatibility_tests::run();
    let source = "# title\r\n[dependencies] # keep\r\n  old = { path = '../old' } # old note\r\n\r\n[package]\r\nname = 'app'\r\n";
    put(source, ["dependencies", "new"], "{ path = '../new' }", "# title\r\n[dependencies] # keep\r\n  old = { path = '../old' } # old note\r\n\"new\" = { path = '../new' }\r\n\r\n[package]\r\nname = 'app'\r\n");
    put(source, ["dependencies", "old"], "{ path = '../other' }", "# title\r\n[dependencies] # keep\r\n  old = { path = '../other' } # old note\r\n\r\n[package]\r\nname = 'app'\r\n");
    remove(source, ["dependencies", "old"], "# title\r\n[dependencies] # keep\r\n   # old note\r\n\r\n[package]\r\nname = 'app'\r\n");
    put("", ["x"], "5", "\"x\" = 5\n");
    put("# note", ["x"], "5", "\"x\" = 5\n# note");
    put("x=1 # note", ["y"], "2", "x=1 # note\n\"y\" = 2\n");
    put("x=1\n[a]\nx=2", ["y"], "3", "x=1\n\"y\" = 3\n[a]\nx=2");
    put("[a] # note", ["a", "x"], "1", "[a] # note\n\"x\" = 1\n");
    put("[a]\n# note\n[z]\nx=1", ["a", "x"], "1", "[a]\n\"x\" = 1\n# note\n[z]\nx=1");
    put("a.b=1", ["a", "c"], "2", "a.b=1\n\"a\".\"c\" = 2\n");
    put("[a]\nb.c=1", ["a", "b", "d"], "2", "[a]\nb.c=1\n\"b\".\"d\" = 2\n");
    put("[a.b]\nx=1", ["a", "c"], "2", "\"a\".\"c\" = 2\n[a.b]\nx=1");
    put("# note\n[package]\nname='app'", ["dependencies", "helper"], "{path='../lib'}", "\"dependencies\".\"helper\" = {path='../lib'}\n# note\n[package]\nname='app'");
    put("['a.b']\n'c.d'=1 # keep", ["a.b", "c.d"], "0x2A", "['a.b']\n'c.d'=0x2A # keep");
    put("", ["世界", "🦆.é"], "'hello'", "\"世界\".\"🦆.é\" = 'hello'\n");
    put("", ["", "x\n\0"], "1", "\"\".\"x\\n\\u0000\" = 1\n");
    let multiline = "a='''\n[dependencies]\n# not a comment\n''' # tail\nb=[1,\n# array note\n2]\n";
    put(multiline, ["a"], "'new'", "a='new' # tail\nb=[1,\n# array note\n2]\n");
    put(multiline, ["b"], "[3,4]", "a='''\n[dependencies]\n# not a comment\n''' # tail\nb=[3,4]\n");
    remove("a.b=1 # b\na.c=2 # c\n", ["a", "b"], " # b\na.c=2 # c\n");
    remove("[a.b] # b\nx=1 # x\n[z]\nx=2\n[a.b.c]\ny=3\n", ["a", "b"], " # b\n # x\n[z]\nx=2\n\n\n");
    remove("[[a]]\nx=1\n[[a]]\nx=2\n[z]\ny=3\n", ["a"], "\n\n\n\n[z]\ny=3\n");
    remove("a={x=1}\nb=2", ["a"], "\nb=2");
    remove("a=1 # keep", ["missing"], "a=1 # keep");
    reject("a={x=1}", ["a", "x"], "2");
    reject("a={x=1}", ["a", "y"], "2");
    reject("a=1", ["a", "x"], "2");
    reject("[a]\nx=1", ["a"], "2");
    reject("a=1", [], "2");
    reject("a=1", ["\xff"], "2");
    reject("a=1", ["b"], "1\nz=2");
    reject("a=1", ["b"], "1\n[v.a]\nx=2");
    reject("a=1", ["b"], "'\xff'");
    reject("a=1", ["b"], "# missing value");
    reject("a=1\na=2", ["b"], "2");
    reject("a='\xff'", ["b"], "2");
    reject("a={x=1,}", ["b"], "2");
    let no_remove, no_remove_error = toml_source::remove("a={x=1}", ["a", "x"]);
    assert(no_remove.len == 0 && no_remove_error.len > 0);
    put("a={x=1,}\n", ["a"], "{x=2,}", "a={x=2,}\n", toml::Version.V1_1);
    var large = str("#"); for i in 1048575 { large.push('x'); }
    reject(large, ["x"], "1");
    large.push('x'); reject(large, ["x"], "1");
    var path: (const u8[:])[>..] = [];
    for i in 65 { path.push("x"); }
    reject("", path, "1");
    var key: u8[>..] = []; for i in 4097 { key.push('x'); }
    let long_path: (const u8[:])[1] = [key];
    reject("", long_path, "1");
    put("", ["\x7f"], "1", "\"\\u007f\" = 1\n");
    remove("a.b=1\n", ["a", "b"], "\n");
    remove("[a.b]\nx=1\n", ["a", "b"], "\n\n");
    for byte in 128 {
        var key: u8[>..] = []; key.push(byte as u8);
        let path: (const u8[:])[1] = [key];
        let output, error = toml_source::put("", path, "1");
        assert(error.len == 0);
        var doc = toml::Document { .. };
        assert(toml::parse_into(output, doc).len == 0);
        let id = toml::find(doc, 0, key);
        assert(id > 0 && doc.nodes[id].integer == 1);
    }
    print("Source-preserving editor tests passed");
}
