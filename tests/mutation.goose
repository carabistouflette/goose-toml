// SPDX-License-Identifier: Apache-2.0
import toml from "..";
import std;

// The oracle uses fixed key slots and ordinary indexed arrays. It shares no
// node IDs, sibling links, hash index, retirement logic or serializer with TOML.
// Tags are integer, float, boolean, string, table and array, respectively.
struct Expected {
    tag: i64 = 0, integer: i64 = 0, number: f64 = 0.0, boolean: bool = false, text: i64 = 0,
}
struct Slot {
    present:  bool = false, value: Expected, length: i64 = 0,
    occupied: bool[8], entries: Expected[8],
}
fn sample_text(choice: i64) -> const u8[:] {
    let choices = ["", "plain", "\0\x7f\n\t", "é😀🪿", "\"\\quoted", "key0", "field0", "a.b"];
    return choices[choice];
}
fn generate(random: rng&, containers: bool) -> Expected {
    let tag = rand_int(random, if containers { 6 } else { 4 });
    let magnitude = (rand_u64(random) & 0x7fffffffffffffff) as i64;
    let floats = [-0.0, 0.0, 5e-324, 1.7976931348623157e308, 1.0000000000000002, -12.5, 1e-100, -1e100];
    return Expected {
        tag:    tag, integer: if rand_int(random, 2) == 0 { -magnitude } else { magnitude },
        number: floats[rand_int(random, floats.len)], boolean: rand_int(random, 2) == 0, text: rand_int(random, 8),
    };
}
fn input(value: Expected) -> toml::Input {
    if value.tag == 0 { return toml::Input.Integer { value: value.integer }; }
    if value.tag == 1 { return toml::Input.Float { value: value.number }; }
    if value.tag == 2 { return toml::Input.Boolean { value: value.boolean }; }
    if value.tag == 3 { return toml::Input.String { value: sample_text(value.text) }; }
    if value.tag == 4 { return toml::Input.Table; }
    return toml::Input.Array;
}
fn compare_value(doc: toml::Document&, id: i64, value: Expected) {
    assert(id >= 0 && id < doc.nodes.len);
    let node = doc.nodes[id];
    if value.tag == 0 { assert(node.kind == toml::Kind.Integer && node.integer == value.integer); }
    else if value.tag == 1 { assert(node.kind == toml::Kind.Float && float_text::bits_of(node.number) == float_text::bits_of(value.number)); }
    else if value.tag == 2 { assert(node.kind == toml::Kind.Boolean && node.boolean == value.boolean); }
    else if value.tag == 3 { assert(node.kind == toml::Kind.String && toml::text(doc, id) == sample_text(value.text)); }
    else if value.tag == 4 { assert(node.kind == toml::Kind.Table); }
    else { assert(value.tag == 5 && node.kind == toml::Kind.Array); }
}
fn compare_model(doc: toml::Document&, model: const Slot[:]) {
    var present = 0;
    for slot, i in model {
        let id = toml::find(doc, 0, str("key", i));
        if !slot.present { assert(id == -1); continue; }
        present++; compare_value(doc, id, slot.value);
        if slot.value.tag == 4 {
            var members = 0;
            for exists, field in slot.occupied {
                let child = toml::find(doc, id, str("field", field));
                if !exists { assert(child == -1); continue; }
                members++; compare_value(doc, child, slot.entries[field]);
            }
            assert(doc.nodes[id].count == members && members == slot.length);
        } else if slot.value.tag == 5 {
            assert(doc.nodes[id].count == slot.length);
            var child = doc.nodes[id].first;
            for at in slot.length { assert(child >= 0); compare_value(doc, child, slot.entries[at]); child = doc.nodes[child].next; }
            assert(child == -1);
        } else { assert(doc.nodes[id].count == 0); }
    }
    assert(doc.nodes[0].count == present);
}
recursive fn walk(doc: toml::Document&, id: i64, parent: i64, depth: i64, visited: bool[:]) {
    assert(id >= 0 && id < doc.nodes.len && !visited[id]); visited[id] = true;
    let node = doc.nodes[id]; assert(node.parent == parent && node.depth == depth);
    var child = node.first; var count = 0; var last = -1;
    while child != -1 {
        assert(count < doc.nodes.len && child > 0 && child < doc.nodes.len);
        assert(node.kind == toml::Kind.Table || node.kind == toml::Kind.Array);
        if node.kind == toml::Kind.Table { assert(toml::find(doc, id, toml::key(doc, child)) == child); }
        walk(doc, child, id, depth + 1, visited);
        last = child; child = doc.nodes[child].next; count++;
    }
    assert(count == node.count && last == node.last);
}
fn invariants(doc: toml::Document&, retired: bool[>..]&) {
    assert(doc.nodes[0].kind == toml::Kind.Table && doc.nodes[0].next == -1);
    var visited: bool[>..] = []; var indexed: bool[>..] = [];
    for i in doc.nodes.len { visited.push(false); indexed.push(false); }
    while retired.len < doc.nodes.len { retired.push(false); }
    walk(doc, 0, -1, 0, visited);
    var entries = 0;
    for id in doc.index {
        if id == -1 { continue; }
        assert(id > 0 && id < doc.nodes.len && !indexed[id]); indexed[id] = true; entries++;
    }
    assert(entries == doc.indexed);
    if doc.index.len > 0 { assert((doc.index.len & (doc.index.len - 1)) == 0 && doc.index.len >= 2 * doc.indexed); }
    for node, id in doc.nodes {
        assert(!retired[id] || node.parent == -2);
        if node.parent == -2 {
            retired[id] = true; assert(!visited[id] && node.first == -1 && node.last == -1 && node.next == -1 && node.count == 0);
        } else {
            assert(visited[id]);
            if id > 0 { assert(indexed[id] == (doc.nodes[node.parent].kind == toml::Kind.Table)); }
        }
    }
}
fn check_roundtrip(doc: toml::Document&, model: const Slot[:]) {
    let output, error = toml::serialize(doc); assert(error.len == 0);
    var back = toml::Document { .. }; assert(toml::parse_into(output, back).len == 0);
    compare_model(back, model);
    var retired: bool[>..] = []; invariants(back, retired);
}
fn sequence(seed: u64) {
    var random = rng { s: seed }; var doc = toml::Document { .. }; toml::init(doc);
    var model = default<Slot[16]>(); var retired: bool[>..] = [];
    var counts: i64[6] = [0, 0, 0, 0, 0, 0]; var retired_attempts = 0;
    for step in 500 {
        let slot = rand_int(random, model.len); let name = str("key", slot);
        let id = toml::find(doc, 0, name); let action = rand_int(random, 8);
        let previous_nodes = doc.nodes.len;
        if step == 249 {
            assert(toml::set(doc, 0, toml::Input.Table).len == 0);
            model = default<Slot[16]>(); counts[1]++;
        } else if action == 0 || (!model[slot].present && action != 2) {
            let value = generate(random, true); let added, error = toml::put(doc, 0, name, input(value)); assert(error.len == 0);
            assert(if id >= 0 { added == id } else { added >= previous_nodes });
            model[slot] = Slot { present: true, value: value, .. }; counts[0]++;
        } else if action == 1 && model[slot].present {
            let value = generate(random, true); assert(toml::set(doc, id, input(value)).len == 0);
            assert(toml::find(doc, 0, name) == id);
            model[slot] = Slot { present: true, value: value, .. }; counts[1]++;
        } else if action == 2 {
            let removed, error = toml::remove(doc, 0, name); assert(error.len == 0 && removed == model[slot].present);
            model[slot] = Slot { .. }; counts[2]++;
        } else if model[slot].value.tag == 4 {
            let field = rand_int(random, 8); let key = str("field", field); let child = toml::find(doc, id, key);
            if action == 3 || action == 4 || !model[slot].occupied[field] {
                let value = generate(random, false); let added, error = toml::put(doc, id, key, input(value)); assert(error.len == 0);
                assert(if child >= 0 { added == child } else { added >= previous_nodes });
                if !model[slot].occupied[field] { model[slot].length++; }
                model[slot].occupied[field] = true; model[slot].entries[field] = value; counts[0]++;
            } else if action == 5 || action == 6 {
                let removed, error = toml::remove(doc, id, key); assert(removed && error.len == 0);
                model[slot].occupied[field] = false; model[slot].length--; counts[2]++;
            } else {
                let value = generate(random, false); assert(toml::set(doc, child, input(value)).len == 0);
                model[slot].entries[field] = value; counts[1]++;
            }
        } else if model[slot].value.tag == 5 {
            let length = model[slot].length;
            if length == 0 || ((action == 3 || action == 4) && length < 8) {
                let value = generate(random, false); let added, error = toml::push(doc, id, input(value)); assert(error.len == 0 && added >= previous_nodes);
                model[slot].entries[length] = value; model[slot].length++; counts[3]++;
            } else if action == 5 || action == 6 || length == 8 {
                // Include missing and negative positions as no-op erasures.
                let ordinal = rand_int(random, length + 2) - 1;
                let erased, error = toml::erase(doc, id, ordinal); assert(error.len == 0 && erased == (ordinal >= 0 && ordinal < length));
                if erased {
                    for at in ordinal..length - 1 { model[slot].entries[at] = model[slot].entries[at + 1]; }
                    model[slot].length--;
                }
                counts[4]++;
            } else {
                let ordinal = rand_int(random, length); var child = doc.nodes[id].first;
                for at in ordinal { child = doc.nodes[child].next; }
                let value = generate(random, false); assert(toml::set(doc, child, input(value)).len == 0);
                model[slot].entries[ordinal] = value; counts[1]++;
            }
        } else {
            let value = generate(random, true);
            // Exercise replacement via put as well as set without changing order/ID.
            if action % 2 == 0 {
                let added, error = toml::put(doc, 0, name, input(value)); assert(error.len == 0 && added == id); counts[0]++;
            } else { assert(toml::set(doc, id, input(value)).len == 0); counts[1]++; }
            model[slot] = Slot { present: true, value: value, .. };
        }
        assert(doc.nodes.len >= previous_nodes);
        compare_model(doc, model); invariants(doc, retired);
        // A stale physical ID must remain unusable even after later insertions.
        if step % 11 == 0 {
            for dead, retired_id in retired {
                if dead {
                    let nodes = doc.nodes.len; let bytes = doc.bytes.len; let indexed = doc.indexed;
                    assert(toml::set(doc, retired_id, toml::Input.Table).len > 0);
                    let bad, error = toml::put(doc, retired_id, "stale", toml::Input.Array); assert(bad == -1 && error.len > 0);
                    let bad_push, push_error = toml::push(doc, retired_id, toml::Input.Integer { value: 0 }); assert(bad_push == -1 && push_error.len > 0);
                    let bad_remove, remove_error = toml::remove(doc, retired_id, "stale"); assert(!bad_remove && remove_error.len > 0);
                    let bad_erase, erase_error = toml::erase(doc, retired_id, 0); assert(!bad_erase && erase_error.len > 0);
                    assert(doc.nodes.len == nodes && doc.bytes.len == bytes && doc.indexed == indexed);
                    retired_attempts++; counts[5]++; break;
                }
            }
        }
        if step % 25 == 0 { check_roundtrip(doc, model); }
    }
    for count in counts { assert(count > 0); }
    assert(retired_attempts > 0); check_roundtrip(doc, model);
}

fn borrowed_inputs() {
    var doc = toml::Document { .. };
    assert(toml::parse_into("source='copied value'\nt={nested='borrow me'}\na=[]", doc).len == 0);
    let source = toml::find(doc, 0, "source");
    // Goose permits these views into grow-only storage alongside document edits.
    // Inputs are copied during the call, including values in a retiring subtree.
    let same, error = toml::put(doc, 0, toml::key(doc, source), toml::Input.String { value: toml::text(doc, source) });
    assert(error.len == 0 && same == source && toml::text(doc, source) == "copied value");
    let new_key, key_error = toml::put(doc, 0, toml::text(doc, source), toml::Input.String { value: toml::key(doc, source) });
    assert(key_error.len == 0 && toml::find(doc, 0, "copied value") == new_key && toml::text(doc, new_key) == "source");
    assert(toml::set(doc, source, toml::Input.String { value: toml::text(doc, new_key) }).len == 0);
    assert(toml::text(doc, source) == "source");
    let table = toml::find(doc, 0, "t"); let nested = toml::find(doc, table, "nested");
    assert(toml::set(doc, table, toml::Input.String { value: toml::text(doc, nested) }).len == 0);
    assert(doc.nodes[nested].parent == -2 && toml::text(doc, table) == "borrow me");
    let array = toml::find(doc, 0, "a");
    let pushed, push_error = toml::push(doc, array, toml::Input.String { value: toml::text(doc, table) });
    assert(push_error.len == 0 && toml::text(doc, pushed) == "borrow me");
    let removed, remove_error = toml::remove(doc, 0, toml::key(doc, new_key)); assert(removed && remove_error.len == 0);
    // Removed node bytes still exist until init/compact and can be copied safely.
    let restored, restored_error = toml::put(doc, 0, toml::key(doc, new_key), toml::Input.String { value: toml::text(doc, new_key) });
    assert(restored_error.len == 0 && restored != new_key && toml::text(doc, restored) == "source");
    let output, write_error = toml::serialize(doc); assert(write_error.len == 0);
    var back = toml::Document { .. }; assert(toml::parse_into(output, back).len == 0);
    assert(toml::text(back, toml::find(back, 0, "source")) == "source");
    assert(toml::text(back, toml::find(back, 0, "t")) == "borrow me");
}
fn main() {
    let seeds: u64[4] = [20261104, 1, 0x12345678, 0x7fffffffffffffff];
    for seed in seeds { sequence(seed); }
    borrowed_inputs(); print("toml mutation sequence tests passed");
}
