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
    reject("a=[", ["a"], "1\n\xff", "toml-edit: invalid replacement UTF-8");
    let v11_source, v11_source_error = toml_source::legacy_remove("a={x=1,}", ["absent"]);
    assert(v11_source.len == 0 && v11_source_error.len > 0);
    // Independently valid fragments can exceed the combined key/value depth.
    var nesting: (const u8[:])[>..] = []; for i in 64 { nesting.push("x"); }
    let nested, nested_error = toml_source::legacy_set("", nesting, "[1]");
    assert(nested.len == 0 && nested_error.len > 0);
    // Several encoded components, including control bytes, exercise reservation
    // after separators and exact output cap without an enormous argv string.
    var controls:     u8[>..]          = []; for i in 174760 { controls.push(0); }
    var control_path: (const u8[:])[2] = ["t", controls];
    let exact, exact_error = toml_source::legacy_set("", control_path, "100000");
    assert(exact_error.len == 0 && exact.len == 1048576);
    reject("", control_path, "1000000", "toml-edit: output exceeds 1 MiB");
    controls.push(0); control_path[1] = controls;
    reject("", control_path, "1", "toml-edit: output exceeds 1 MiB");
    controls.push(0); control_path[1] = controls;
    reject("", control_path, "1", "toml-edit: rendered path exceeds 1 MiB");
    var wide: u8[>..] = [];
    for i in 65534 { wide.push('k'); format(wide, i); wide.append("=0\n"); }
    let last, last_error = toml_source::legacy_set(wide, ["last"], "1");
    assert(last_error.len == 0);
    let exhausted, exhausted_error = toml_source::legacy_set(last, ["overflow"], "1");
    assert(exhausted.len == 0 && exhausted_error.len > 0);
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
