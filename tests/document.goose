// SPDX-License-Identifier: Apache-2.0
import toml from "..";
import std;

fn insert(doc: toml::Document&, parent: i64, name: const u8[:], input: toml::Input) -> i64 {
    let id, error = toml::put(doc, parent, name, input);
    if error.len > 0 { print(error); }
    assert(error.len == 0 && id > 0);
    return id;
}
fn append(doc: toml::Document&, parent: i64, input: toml::Input) -> i64 {
    let id, error = toml::push(doc, parent, input);
    if error.len > 0 { print(error); }
    assert(error.len == 0 && id > 0);
    return id;
}
fn construction() {
    var doc = toml::Document { .. }; toml::init(doc);
    assert(doc.nodes.len == 1 && doc.nodes[0].parent == -1 && doc.nodes[0].count == 0);
    let table = insert(doc, 0, "literal.dot", toml::Input.Table);
    let array = insert(doc, table, "", toml::Input.Array);
    let integer = append(doc, array, toml::Input.Integer { value: -9223372036854775808 });
    append(doc, array, toml::Input.Float { value: -0.0 });
    append(doc, array, toml::Input.Boolean { value: true });
    let nested = append(doc, array, toml::Input.Table);
    let string = insert(doc, nested, "é😀", toml::Input.String { value: "\0\x7f\n🪿" });
    let date = insert(doc, 0, "date", toml::Input.DateTime { kind: toml::Kind.LocalDate, value: "2024-02-29" });
    assert(toml::find(doc, 0, "literal.dot") == table && toml::find(doc, table, "") == array);
    assert(doc.nodes[integer].integer == -9223372036854775808 && doc.nodes[array].count == 4);
    assert(toml::text(doc, string) == "\0\x7f\n🪿" && toml::text(doc, date) == "2024-02-29");
    let output, error = toml::serialize(doc); assert(error.len == 0);
    var back = toml::Document { .. }; assert(toml::parse_into(output, back).len == 0);
    let out_table = toml::find(back, 0, "literal.dot"); assert(out_table > 0);
    assert(back.nodes[toml::find(back, out_table, "")].count == 4);
}
fn ownership(doc: toml::Document&) {
    var name = str("owned"); var value = str("value");
    insert(doc, 0, name, toml::Input.String { value: value });
    name.clear(); name.append("mutated"); value.clear(); value.append("changed");
}
fn replacement_removal() {
    var doc = toml::Document { .. };
    assert(toml::parse_into("first=1\nt={child={deep=2}}\nlast=3\na=[{x=1},2,3]", doc).len == 0);
    let first = toml::find(doc, 0, "first"); let table = toml::find(doc, 0, "t"); let last = toml::find(doc, 0, "last");
    let child = toml::find(doc, table, "child"); let deep = toml::find(doc, child, "deep");
    let old_next = doc.nodes[table].next; let physical = doc.nodes.len;
    assert(insert(doc, 0, "t", toml::Input.String { value: "replaced" }) == table);
    assert(doc.nodes.len == physical && doc.nodes[first].next == table && doc.nodes[table].next == old_next);
    assert(toml::key(doc, table) == "t" && toml::text(doc, table) == "replaced");
    assert(doc.nodes[child].parent == -2 && doc.nodes[deep].parent == -2);
    assert(toml::set(doc, deep, toml::Input.Table).len > 0 && toml::find(doc, child, "deep") == -1);
    assert(toml::set(doc, table, toml::Input.Table).len == 0);
    let fresh = insert(doc, table, "child", toml::Input.Boolean { value: true }); assert(fresh >= physical && fresh != child);
    let removed, error = toml::remove(doc, 0, "t"); assert(removed && error.len == 0);
    assert(toml::find(doc, 0, "t") == -1 && doc.nodes[first].next == last && doc.nodes[fresh].parent == -2);
    let missing, missing_error = toml::remove(doc, 0, "t"); assert(!missing && missing_error.len == 0);
    let newer = insert(doc, 0, "t", toml::Input.Integer { value: 9 }); assert(newer > fresh);
    assert(toml::find(doc, 0, "t") == newer && doc.nodes[doc.nodes[0].last].integer == 9);
    let array = toml::find(doc, 0, "a"); let element = doc.nodes[array].first; let x = toml::find(doc, element, "x");
    let erased, erase_error = toml::erase(doc, array, 0); assert(erased && erase_error.len == 0);
    assert(doc.nodes[element].parent == -2 && doc.nodes[x].parent == -2 && doc.nodes[array].count == 2);
    assert(doc.nodes[doc.nodes[array].first].integer == 2);
    let tail, tail_error = toml::erase(doc, array, 1); assert(tail && tail_error.len == 0);
    assert(doc.nodes[array].last == doc.nodes[array].first && doc.nodes[doc.nodes[array].last].next == -1);
    let final, final_error = toml::erase(doc, array, 0); assert(final && final_error.len == 0);
    assert(doc.nodes[array].first == -1 && doc.nodes[array].last == -1 && doc.nodes[array].count == 0);
    let absent, absent_error = toml::erase(doc, array, -1); assert(!absent && absent_error.len == 0);
    let beyond, beyond_error = toml::erase(doc, array, 0); assert(!beyond && beyond_error.len == 0);
    // Parsed inline table seals are parser declaration rules, not edit locks.
    assert(toml::parse_into("inline={a={b=1}}", doc).len == 0);
    let inline = toml::find(doc, 0, "inline"); let a = toml::find(doc, inline, "a");
    insert(doc, a, "c", toml::Input.Integer { value: 2 });
    ownership(doc); assert(toml::text(doc, toml::find(doc, 0, "owned")) == "value");
    assert(toml::set(doc, 0, toml::Input.Table).len == 0 && doc.nodes[0].count == 0);
    assert(toml::find(doc, 0, "inline") == -1);
    toml::init(doc); assert(doc.nodes.len == 1 && doc.bytes.len == 0 && doc.index.len == 0 && doc.indexed == 0);
}
fn index_churn() {
    var doc = toml::Document { .. }; toml::init(doc);
    for i in 1500 {
        let name = str("key", i % 40);
        let id = insert(doc, 0, name, toml::Input.Integer { value: i });
        assert(toml::find(doc, 0, name) == id);
        if i % 3 != 0 { let removed, error = toml::remove(doc, 0, name); assert(removed && error.len == 0); }
    }
    for i in 40 {
        let name = str("key", i);
        let id = insert(doc, 0, name, toml::Input.Integer { value: i });
        assert(toml::find(doc, 0, name) == id && doc.nodes[id].integer == i);
    }
    let old_nodes = doc.nodes.len; let old_bytes = doc.bytes.len;
    assert(toml::compact(doc).len == 0);
    assert(doc.nodes.len == 41 && doc.bytes.len < old_bytes && doc.nodes.len < old_nodes);
    for i in 40 { assert(doc.nodes[toml::find(doc, 0, str("key", i))].integer == i); }
}
fn errors_and_limits() {
    var doc = toml::Document { .. };
    let absent, absent_error = toml::put(doc, 0, "a", toml::Input.Table); assert(absent == -1 && absent_error.len > 0);
    toml::init(doc);
    assert(toml::set(doc, 0, toml::Input.Integer { value: 1 }).len > 0);
    assert(toml::set(doc, -1, toml::Input.Table).len > 0 && toml::set(doc, 123, toml::Input.Table).len > 0);
    let wrong, wrong_error = toml::push(doc, 0, toml::Input.Table); assert(wrong == -1 && wrong_error.len > 0);
    let scalar = insert(doc, 0, "scalar", toml::Input.Integer { value: 1 });
    let bad_parent, parent_error = toml::put(doc, scalar, "x", toml::Input.Table); assert(bad_parent == -1 && parent_error.len > 0);
    let bad_key, key_error = toml::put(doc, 0, "\xff", toml::Input.Table); assert(bad_key == -1 && key_error.len > 0);
    let bad_string, string_error = toml::put(doc, 0, "s", toml::Input.String { value: "\xed\xa0\x80" }); assert(bad_string == -1 && string_error.len > 0);
    for kind in [toml::Kind.Integer, toml::Kind.LocalDateTime, toml::Kind.LocalDate] {
        let bad_date, date_error = toml::put(doc, 0, "date", toml::Input.DateTime { kind: kind, value: "2023-02-29" });
        assert(bad_date == -1 && date_error.len > 0);
    }
    insert(doc, 0, "short", toml::Input.DateTime { kind: toml::Kind.LocalTime, value: "07:32" });
    var parent = 0;
    for i in 64 { parent = insert(doc, parent, "child", toml::Input.Table); }
    let too_deep, depth_error = toml::put(doc, parent, "child", toml::Input.Table); assert(too_deep == -1 && depth_error.len > 0);
    toml::init(doc);
    var huge: u8[>..] = []; for i in 1048576 { huge.push('x'); }
    let full = insert(doc, 0, "", toml::Input.String { value: huge });
    assert(doc.bytes.len == 1048576 && toml::set(doc, full, toml::Input.String { value: "x" }).len > 0);
    toml::init(doc);
    let array = insert(doc, 0, "", toml::Input.Array);
    for i in 65534 { append(doc, array, toml::Input.Integer { value: i }); }
    let capped, cap_error = toml::push(doc, array, toml::Input.Integer { value: 0 }); assert(capped == -1 && cap_error.len > 0);
    assert(toml::set(doc, doc.nodes[array].first, toml::Input.Integer { value: 99 }).len == 0);
    let removed, remove_error = toml::erase(doc, array, 0); assert(removed && remove_error.len == 0);
    let still_capped, still_error = toml::push(doc, array, toml::Input.Table); assert(still_capped == -1 && still_error.len > 0);
}
fn main() {
    construction(); replacement_removal(); index_churn(); errors_and_limits();
    print("toml document tests passed");
}
