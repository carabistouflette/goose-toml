// SPDX-License-Identifier: Apache-2.0
namespace compatibility_tests;
import toml from "../..";
import toml.source.editor;
import std;
fn reject(source: const u8[:], path: const u8[:][:], value: const u8[:], expected: const u8[:]) {
    let output, error = toml_source::legacy_set(source, path, value);
    if error != expected { print("Expected: ", expected, "\nActual: ", error); }
    assert(output.len == 0 && error == expected);
}
fn run() {
    let suffix = "toml-edit: replacement must be exactly one value without a trailing comment or newline";
    reject("a=[", ["a"], "1\nv=bad", suffix);
    reject("a=[", [], "", "toml-edit: path needs 1..64 decoded components");
    reject("a=[", ["a"], "", "toml-edit: empty or oversized replacement");
    reject("a=[", ["a"], "\xff", "toml-edit: invalid replacement UTF-8");
    reject("", ["\xff"], "[", "toml-edit: invalid or oversized key path");
    reject("", ["x"], "[", "toml: invalid decimal integer part at byte 5 (line 1, byte column 6)");
    reject("", ["x"], "{a=1,}", "toml: expected key at byte 9 (line 1, byte column 10)");
    for source in ["a=1", "a=[1]", "a={x=1}", "[[a]]\nx=1"] {
        let output, error = toml_source::legacy_remove(source, ["a", "absent"]);
        assert(output.len == 0 && error == "toml-edit: cannot traverse an array, scalar or inline table");
    }
    var key:  u8[>..]          = []; for i in 174762 { key.push('x'); }
    var path: (const u8[:])[1] = [key];
    let accepted, accepted_error = toml_source::legacy_set("", path, "1");
    assert(accepted_error.len == 0 && accepted.len == key.len + 7);
    key.push('x'); path[0] = key;
    reject("", path, "1", "toml-edit: rendered path exceeds 1 MiB");
    // The conservative encoded bound only applies to new insertion, never a
    // replacement/removal of an existing long key.
    var source: u8[>..] = []; source.push('"'); source.append(key); source.append("\"=0");
    let replaced, replaced_error = toml_source::legacy_set(source, path, "2");
    assert(replaced_error.len == 0 && replaced.len == source.len && replaced[replaced.len - 1] == '2');
    let removed, removed_error = toml_source::legacy_remove(source, path);
    assert(removed_error.len == 0 && removed.len == 0);
    for i in 1048576 - key.len { key.push('x'); }
    path[0] = key;
    let missing, missing_error = toml_source::legacy_remove("a=1", path);
    assert(missing_error.len == 0 && missing == "a=1");
    key.push('x'); path[0] = key;
    reject("", path, "1", "toml-edit: invalid or oversized key path");
    var deep: (const u8[:])[>..] = []; for i in 64 { deep.push("x"); }
    let deep_out, deep_error = toml_source::legacy_remove("", deep);
    assert(deep_error.len == 0 && deep_out.len == 0);
    deep.push("x"); reject("", deep, "1", "toml-edit: path needs 1..64 decoded components");
    var cap: u8[>..] = []; cap.push('#'); for i in 1048575 { cap.push('x'); }
    let copied, copied_error = toml_source::legacy_remove(cap, ["absent"]);
    assert(copied_error.len == 0 && copied == cap);
    cap[1] = 'y'; assert(copied[1] == 'x'); // Independent owned output.
    reject(cap, ["new"], "1", "toml-edit: output exceeds 1 MiB");
    cap.push('x'); reject(cap, ["new"], "1", "toml-edit: input exceeds 1 MiB");
    print("Legacy compatibility profile boundary tests passed");
}
