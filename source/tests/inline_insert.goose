// SPDX-License-Identifier: Apache-2.0
namespace inline_insert_tests;
import toml from "../..";
import toml.source.editor;
import inline_values;
import std;
fn run() {
    inline_tests::replace("v={}", ["v", "x"], "1", "v={\"x\" = 1}");
    inline_tests::replace("v={  } # keep", ["v", "x"], "1", "v={\"x\" = 1  } # keep");
    inline_tests::replace("v={old=1}", ["v", "new"], "2", "v={\"new\" = 2, old=1}");
    inline_tests::replace("v={a={old=1},b=2}", ["v", "a", "new"], "3", "v={a={\"new\" = 3, old=1},b=2}");
    inline_tests::replace("v={a.b=1}", ["v", "a", "c"], "2", "v={\"a\".\"c\" = 2, a.b=1}");
    inline_tests::replace("v={a.b={c=1},z=2}", ["v", "a", "b", "d"], "3", "v={a.b={\"d\" = 3, c=1},z=2}");
    inline_tests::replace("v={}", ["v", "a", "b"], "[1,2]", "v={\"a\".\"b\" = [1,2]}");
    inline_tests::replace("v={'a.b'={}}", ["v", "a.b", ""], "true", "v={'a.b'={\"\" = true}}");
    inline_tests::replace("v={}", ["v", "世界", "\0\x7f"], "'🦆'", "v={\"世界\".\"\\u0000\\u007f\" = '🦆'}");
    inline_tests::replace("#keep\r\n[a]\nv={old=1}\r\n[z]\nx=2", ["a", "v", "new"], "2", "#keep\r\n[a]\nv={\"new\" = 2, old=1}\r\n[z]\nx=2");
    inline_tests::replace("v={x=1,}", ["v", "new"], "2", "v={\"new\" = 2, x=1,}", toml::Version.V1_1);
    inline_tests::replace("v={# keep\r\n}", ["v", "new"], "2", "v={\"new\" = 2# keep\r\n}", toml::Version.V1_1);
    inline_tests::replace("v={# keep\n old=1, #tail\n}", ["v", "new"], "2", "v={\"new\" = 2, # keep\n old=1, #tail\n}", toml::Version.V1_1);
    inline_tests::replace("v={old=1}", ["v", "new"], "2 #new\n", "v={\"new\" = 2 #new\n, old=1}", toml::Version.V1_1);
    inline_tests::reject("v={old=1}", ["v", "new"], "2 #swallows comma");
    inline_tests::reject("v={a=1}", ["v", "a", "x"], "2");
    inline_tests::reject("v={a=[{}]}", ["v", "a", "x"], "2");
    inline_tests::reject("v={old=1,}", ["v", "new"], "2");
    let a:     (const u8[:])[2]     = ["v", "a"]; let b: (const u8[:])[2] = ["v", "b"]; let old: (const u8[:])[2] = ["v", "old"];
    let edits: toml_source::Edit[3] = [inline_tests::edit(a, "1"), inline_tests::edit(b, "2"), inline_tests::edit(old, "3")];
    let empty, error = toml_source::apply("v={}", edits); assert(error.len == 0 && empty == "v={\"a\" = 1, \"b\" = 2, \"old\" = 3}");
    let filled, filled_error = toml_source::apply("v={old=0}", edits); assert(filled_error.len == 0 && filled == "v={\"a\" = 1, \"b\" = 2, old=3}");
    let ab:       (const u8[:])[3]     = ["v", "a", "b"]; let ac: (const u8[:])[3] = ["v", "a", "c"];
    let siblings: toml_source::Edit[2] = [inline_tests::edit(ab, "1"), inline_tests::edit(ac, "2")];
    let shared, shared_error = toml_source::apply("v={}", siblings); assert(shared_error.len == 0 && shared == "v={\"a\".\"b\" = 1, \"a\".\"c\" = 2}");
    let reverse: toml_source::Edit[2] = [inline_tests::edit(b, "1"), inline_tests::edit(a, "2")];
    let ordered, ordered_error = toml_source::apply("v={old=0,}", reverse, toml::Version.V1_1); assert(ordered_error.len == 0 && ordered == "v={\"b\" = 1, \"a\" = 2, old=0,}");
    let legacy, legacy_error = toml_source::legacy_set("v={}", a, "1"); assert(legacy.len == 0 && legacy_error == "toml-edit: cannot traverse an array, scalar or inline table");
    let fail, retained = toml_source::apply("v={}", [inline_tests::edit(a, "1"), inline_tests::edit(b, "[1 #bad")]); assert(fail.len == 0 && retained.len > 0);
    var saved: u8[>..]                = []; saved.append(retained); inline_tests::replace("v={}", a, "1", "v={\"a\" = 1}"); assert(saved == retained);
    var keys:  u8[>..]                = []; var ends: i64[>..] = []; for i in 64 { format(keys, "key", i); ends.push(keys.len); }
    var parts: (const u8[:])[>..]     = []; var start = 0; for end in ends { parts.push("v"); parts.push(keys[start..end]); start = end; }
    var all:   toml_source::Edit[>..] = []; var expected: u8[>..] = []; expected.append("v={");
    for i in 64 { all.push(inline_tests::edit(parts[i * 2..i * 2 + 2], "1")); if i > 0 { expected.append(", "); } format(expected, "\"key", i, "\" = 1"); } expected.push('}');
    let full, full_error = toml_source::apply("v={}", all); assert(full_error.len == 0 && full == expected);
    var padded: u8[>..] = []; padded.append("#"); for i in 1048576 - 13 { padded.push(' '); } padded.append("\nv={}");
    assert(padded.len == 1048569); var exact: u8[>..] = []; exact.append(padded[..padded.len - 1]); exact.append("\"a\" = 1}");
    inline_tests::replace(padded, a, "1", exact); inline_tests::reject(padded, a, "22");
    var dense: u8[>..] = []; dense.append("v={keep=["); for i in 65533 { dense.append("1,"); } dense.append("]}"); inline_tests::reject(dense, a, "1");
    var deep:  u8[>..] = []; deep.append("v="); var path: (const u8[:])[>..] = ["v"];
    for i in 62 { deep.append("{x="); path.push("x"); } deep.append("{}"); for i in 62 { deep.push('}'); } path.push("new"); inline_tests::reject(deep, path, "[1]");
    var borrowed: u8[>..] = []; borrowed.append("v={old='new'}");
    let borrowed_path: (const u8[:])[2] = [borrowed[..1], borrowed[8..11]];
    let alias_output, alias_error = toml_source::put(borrowed, borrowed_path, borrowed[7..12]);
    let alias_batch, alias_batch_error = toml_source::apply(borrowed, [inline_tests::edit(borrowed_path, borrowed[7..12])]);
    assert(alias_error.len == 0 && alias_batch_error.len == 0);
    borrowed[0] = 'w'; borrowed[8] = 'N';
    assert(alias_output == "v={\"new\" = 'new', old='new'}" && alias_batch == alias_output);
    print("Inline member insertion checks passed");
}
