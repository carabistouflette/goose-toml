// SPDX-License-Identifier: Apache-2.0
namespace reuse_lifetime_tests;
import toml from "../..";
import toml.source.editor;
import std;
fn put(source: const u8[:], path: const u8[:][:], value: const u8[:], legacy: bool) -> u8[>..], u8[>..] {
    if legacy { return toml_source::legacy_set(source, path, value); }
    return toml_source::put(source, path, value);
}
fn remove(source: const u8[:], path: const u8[:][:], legacy: bool) -> u8[>..], u8[>..] {
    if legacy { return toml_source::legacy_remove(source, path); }
    return toml_source::remove(source, path);
}
fn run() {
    var value: u8[>..] = []; value.push('[');
    for i in 1024 { if i > 0 { value.push(','); } value.append("'decoded text'"); }
    value.push(']');
    var expected: u8[>..] = []; expected.append("x="); expected.append(value); expected.append(" # tail");
    for legacy in [false, true] {
        let grown, grown_error = put("x=1 # tail", ["x"], value, legacy);
        assert(grown_error.len == 0 && grown == expected);
        // Final parsing shrinks a large source document to comments only.
        let shrunk, shrunk_error = remove(grown, ["x"], legacy);
        assert(shrunk_error.len == 0 && shrunk == " # tail");
        // Header/subtree selection must finish before original nodes are reset.
        let scattered = "[a.b]\nx='old'\n[z]\ny=2\n[a.b.c]\nx='child'";
        let removed, removed_error = remove(scattered, ["a", "b"], legacy);
        assert(removed_error.len == 0 && removed == "\n\n[z]\ny=2\n\n");
        // The caller can lend path and replacement slices of the same source.
        var source: u8[>..] = []; source.append("x='borrowed'");
        let path: (const u8[:])[1] = [source[..1]];
        let borrowed, borrowed_error = put(source, path, source[2..], legacy);
        source[0] = 'y';
        assert(borrowed_error.len == 0 && borrowed == "x='borrowed'");
    }
    print("Terminal document reuse lifetime checks passed");
}
