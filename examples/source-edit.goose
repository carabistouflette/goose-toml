// SPDX-License-Identifier: Apache-2.0
import toml from "..";
import toml.source.editor;
import std;
fn main() {
    let source = "dependencies = { old = {path='../old'} } # keep\n";
    let old_path: (const u8[:])[2] = ["dependencies", "old"];
    let new_path: (const u8[:])[2] = ["dependencies", "helper"];
    let edits: toml_source::Edit[2] = [
        toml_source::Edit.Put {path: old_path, value: "{path='../updated'}"},
        toml_source::Edit.Put {path: new_path, value: "{path='../helper'}"},
    ];
    let output, error = toml_source::apply(source, edits);
    if error.len > 0 { print(error); return; }
    assert(output == "dependencies = {\"helper\" = {path='../helper'},  old = {path='../updated'} } # keep\n");
    print(output);
}
