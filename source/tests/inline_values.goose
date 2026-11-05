// SPDX-License-Identifier: Apache-2.0
namespace inline_tests;
import toml from "../..";
import toml.source.editor;
import std;
fn edit(path: const u8[:][:], value: const u8[:]) -> toml_source::Edit { return toml_source::Edit.Put { path: path, value: value }; }
fn replace(source: const u8[:], path: const u8[:][:], value: const u8[:], expected: const u8[:], version: toml::Version = toml::Version.V1_0) {
    let output, error = toml_source::put(source, path, value, version);
    if error.len > 0 { print(error); } assert(error.len == 0 && output == expected);
    let batch, batch_error = toml_source::apply(source, [edit(path, value)], version);
    if batch_error.len > 0 { print(batch_error); } assert(batch_error.len == 0 && batch == expected);
}
fn reject(source: const u8[:], path: const u8[:][:], value: const u8[:], version: toml::Version = toml::Version.V1_0) {
    let output, error = toml_source::put(source, path, value, version);
    let batch, batch_error = toml_source::apply(source, [edit(path, value)], version);
    assert(output.len == 0 && error.len > 0 && batch.len == 0 && batch_error.len > 0);
}
fn run() {
    replace("# keep\r\ndeps = { a={path='../old'}, b = [1, 2] } # tail\r\n", ["deps", "a", "path"], "'../new'",
        "# keep\r\ndeps = { a={path='../new'}, b = [1, 2] } # tail\r\n");
    replace("v={a.b=0x10, a.c='stay'}", ["v", "a", "b"], "0x20", "v={a.b=0x20, a.c='stay'}");
    replace("v={'a.b'={ 'q' = 1 }, a.b=2}", ["v", "a.b", "q"], "true", "v={'a.b'={ 'q' = true }, a.b=2}");
    replace("v={\"\\u0000\"={''=1}, \"世界\"=2}", ["v", "\0", ""], "'🦆'", "v={\"\\u0000\"={''='🦆'}, \"世界\"=2}");
    replace("before=[{k=1},2]\n[a]\nv={x=1, y={z=2}}\nafter='keep'", ["a", "v", "y", "z"], "{k=[1,2]}",
        "before=[{k=1},2]\n[a]\nv={x=1, y={z={k=[1,2]}}}\nafter='keep'");
    replace("[a.b]\nv={x=1}\n[z]\ny=2\n[a]\nlater={w=3}", ["a", "later", "w"], "4",
        "[a.b]\nv={x=1}\n[z]\ny=2\n[a]\nlater={w=4}");
    replace("v={x={a=1},y=2}", ["v", "x"], "[true,false]", "v={x=[true,false],y=2}");
    replace("v={x=[{a=1},2],y=3}", ["v", "y"], "false", "v={x=[{a=1},2],y=false}");
    replace("v={x='''[not.a.header], { k=\" }''',y=1}", ["v", "y"], "2", "v={x='''[not.a.header], { k=\" }''',y=2}");
    replace("v={x=[1,\n# inside array\n2],y=1}", ["v", "x"], "[3]", "v={x=[3],y=1}");
    replace("v={x=1979-05-27 07:32:00Z,y=1}", ["v", "y"], "2", "v={x=1979-05-27 07:32:00Z,y=2}");
    replace("v={\r\n # keep\r\n x={a=1,}, # after\r\n y=2,\r\n}", ["v", "x", "a"], "3",
        "v={\r\n # keep\r\n x={a=3,}, # after\r\n y=2,\r\n}", toml::Version.V1_1);
    replace("v={x=1, y=2}", ["v", "x"], "{a=2,}", "v={x={a=2,}, y=2}", toml::Version.V1_1);
    replace("v={x=1, y=2}", ["v", "x"], "2 # new comment\n", "v={x=2 # new comment\n, y=2}", toml::Version.V1_1);
    reject("v={x=1}", ["v", "missing"], "2");
    reject("v={a.b=1, a.c=2}", ["v", "a"], "2"); // implicit table has no complete value span
    reject("v={x=[{a=1}]}", ["v", "x", "a"], "2");
    reject("v={x=1,}", ["v", "x"], "2");
    reject("v={x=1}", ["v", "x"], "2 # closes original brace");
    reject("v={x=1}", ["v", "x"], "2\nextra=3");
    reject("v={x=1}", ["v", "x"], "'\xff'");
    reject("v={x=1, y=}", ["v", "x"], "2");
    let legacy, legacy_error = toml_source::legacy_set("v={x=1}", ["v", "x"], "2");
    assert(legacy.len == 0 && legacy_error == "toml-edit: cannot traverse an array, scalar or inline table");
    let removed, remove_error = toml_source::remove("v={x=1}", ["v", "x"]);
    assert(removed.len == 0 && remove_error == "toml source: value is inside an unsupported inline span");
    let v_x:      (const u8[:])[2]     = ["v", "x"]; let v_y: (const u8[:])[2] = ["v", "y"]; let w_z: (const u8[:])[2] = ["w", "z"];
    let requests: toml_source::Edit[3] = [edit(v_x, "2"), edit(v_y, "'changed'"), edit(w_z, "false")];
    let batch, batch_error = toml_source::apply("v={x=1,y='old'}\nw={z=true}", requests);
    assert(batch_error.len == 0 && batch == "v={x=2,y='changed'}\nw={z=false}");
    let bad: toml_source::Edit[2] = [edit(v_x, "2"), toml_source::Edit.Remove { path: v_y }];
    let partial, partial_error = toml_source::apply("v={x=1,y=2}", bad);
    assert(partial.len == 0 && find(partial_error, "batch edit 1:") >= 0);
    var borrowed: u8[>..] = []; borrowed.append("v={x='old',y='new'}");
    let aliased, alias_error = toml_source::put(borrowed, v_x, borrowed[13..18]);
    assert(alias_error.len == 0 && aliased == "v={x='new',y='new'}"); borrowed[0] = 'w';
    assert(aliased == "v={x='new',y='new'}");
    var deep: u8[>..] = []; deep.append("v="); var path: (const u8[:])[>..] = ["v"];
    for i in 63 { deep.append("{x="); path.push("x"); }
    let at = deep.len; deep.push('1'); for i in 63 { deep.push('}'); }
    var expected: u8[>..] = []; expected.append(deep[..at]); expected.push('2'); expected.append(deep[at + 1..]);
    replace(deep, path, "2", expected); reject(deep, path, "[1]");
    var dense: u8[>..] = []; dense.append("v={x=1,keep=["); for i in 65532 { dense.append("1,"); } dense.append("]}");
    reject(dense, v_x, "[1]"); // individually valid fragment exceeds combined node cap
    var padded: u8[>..] = []; padded.append("#"); for i in 1048576 - 10 { padded.push(' '); } padded.append("\nv={x=1}");
    assert(padded.len == 1048575);
    var exact: u8[>..] = []; exact.append(padded[..padded.len - 2]); exact.append("22}");
    replace(padded, v_x, "22", exact); reject(padded, v_x, "222");
    var names: u8[>..] = []; var ends: i64[>..] = [];
    var full:  u8[>..] = []; var wanted: u8[>..] = []; full.append("v={"); wanted.append("v={");
    for i in 64 {
        format(names, "key", i); ends.push(names.len);
        if i > 0 { full.push(','); wanted.push(','); }
        format(full, "key", i, "=1"); format(wanted, "key", i, "=2");
    }
    full.push('}'); wanted.push('}');
    var parts: (const u8[:])[>..] = []; var start = 0;
    for end in ends { parts.push("v"); parts.push(names[start..end]); start = end; }
    var all: toml_source::Edit[>..] = [];
    for i in 64 { all.push(edit(parts[i * 2..i * 2 + 2], "2")); }
    let all_output, all_error = toml_source::apply(full, all);
    assert(all_error.len == 0 && all_output == wanted);
    let no_output, retained = toml_source::put("v={x=1}", v_x, "2 # consumes closing brace");
    assert(no_output.len == 0 && retained.len > 0); var saved: u8[>..] = []; saved.append(retained);
    replace("v={x=1}", v_x, "2", "v={x=2}"); assert(saved == retained);
    print("Inline assigned-value replacement checks passed");
}
