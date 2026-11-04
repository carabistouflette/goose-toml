// SPDX-License-Identifier: Apache-2.0
import toml from "../..";
import toml.source.editor;
import std;
fn check_output(output: const u8[:]) {
    var doc = toml::Document { .. };
    assert(toml::parse_into(output, doc).len == 0);
}
export fn fuzz_parse(input: const u8[:]) -> i64 {
    var doc = toml::Document { .. };
    let parse_error = toml::parse_into(input, doc);
    let removed, remove_error = toml_source::remove(input, ["__source_fuzz_probe"]);
    if parse_error.len == 0 && toml::find(doc, 0, "__source_fuzz_probe") < 0 { assert(remove_error.len == 0 && removed == input); }
    if remove_error.len == 0 {
        assert(parse_error.len == 0); check_output(removed);
        if toml::find(doc, 0, "__source_fuzz_probe") < 0 { assert(removed == input); }
    } else { assert(removed.len == 0); }
    let added, add_error = toml_source::put(input, ["__source_fuzz_probe"], "{path='世界'}");
    if add_error.len == 0 { assert(parse_error.len == 0); check_output(added); }
    else { assert(added.len == 0); }
    let split = input.len / 2;
    let edited, edit_error = toml_source::put(input[..split], ["a", "b"], input[split..]);
    if edit_error.len == 0 { check_output(edited); } else { assert(edited.len == 0); }
    let legacy_removed, legacy_remove_error = toml_source::legacy_remove(input, ["__source_fuzz_probe"]);
    if parse_error.len == 0 && toml::find(doc, 0, "__source_fuzz_probe") < 0 { assert(legacy_remove_error.len == 0 && legacy_removed == input); }
    if legacy_remove_error.len == 0 { assert(parse_error.len == 0); check_output(legacy_removed); }
    else { assert(legacy_removed.len == 0); }
    let legacy_added, legacy_add_error = toml_source::legacy_set(input, ["__source_fuzz_probe"], "{path='世界'}");
    if legacy_add_error.len == 0 { assert(parse_error.len == 0); check_output(legacy_added); }
    else { assert(legacy_added.len == 0); }
    let legacy_edited, legacy_edit_error = toml_source::legacy_set(input[..split], ["a", "b"], input[split..]);
    if legacy_edit_error.len == 0 { check_output(legacy_edited); } else { assert(legacy_edited.len == 0); }
    return if parse_error.len == 0 { 1 } else { 0 };
}
export fn fuzz_assertion_probe(value: i64) { assert(value != 0); }
fn main() {}
