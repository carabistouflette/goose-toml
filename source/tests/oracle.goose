// SPDX-License-Identifier: Apache-2.0
import toml from "../..";
import toml.source.editor;
import std;
import os;
fn nibble(c: u8) -> u8 {
    if c >= '0' && c <= '9' { return c - '0'; }
    assert(c >= 'a' && c <= 'f'); return c - 'a' + 10;
}
fn unhex(input: const u8[:]) -> u8[>..] {
    assert(input.len % 2 == 0);
    var bytes: u8[>..] = []; var at = 0;
    while at < input.len { bytes.push(nibble(input[at]) * 16 + nibble(input[at + 1])); at += 2; }
    return bytes;
}
fn hex(input: const u8[:]) -> u8[>..] {
    var output: u8[>..] = []; let digits = "0123456789abcdef";
    for byte in input { output.push(digits[byte >> 4]); output.push(digits[byte & 15]); }
    return output;
}
fn main() {
    var line: u8[>..] = [];
    loop {
        line.clear(); if !read_line(line) { break; }
        let fields = split(line, '\t');
        if fields[0] == "LS" || fields[0] == "LR" || fields[0] == "P0" || fields[0] == "P1" {
            assert(fields.len >= 3);
            let input = unhex(fields[1]); let value = unhex(fields[2]);
            var keys: u8[>..] = []; var ends: i64[>..] = [];
            for field in fields[3..] { let key = unhex(field); keys.append(key); ends.push(keys.len); }
            var path: (const u8[:])[>..] = []; var start = 0;
            for end in ends { path.push(keys[start..end]); start = end; }
            var output: u8[>..] = []; var error: u8[>..] = [];
            if fields[0] == "LS" { let text, err = toml_source::legacy_set(input, path, value); output.append(text); error.append(err); }
            else if fields[0] == "LR" { let text, err = toml_source::legacy_remove(input, path); output.append(text); error.append(err); }
            else { let text, err = toml_source::put(input, path, value, if fields[0] == "P1" { toml::Version.V1_1 } else { toml::Version.V1_0 }); output.append(text); error.append(err); }
            assert(error.len == 0 || output.len == 0);
            print(if error.len > 0 { "E" } else { "O" }, "\t", hex(output), "\t", hex(error));
            continue;
        }
        assert(fields.len == 5);
        let input = unhex(fields[1]); let table = unhex(fields[2]); let key = unhex(fields[3]); let value = unhex(fields[4]);
        let path: (const u8[:])[2] = [table, key];
        var output: u8[>..] = []; var error: u8[>..] = [];
        if fields[0] == "P" { let text, err = toml_source::put(input, path, value); output.append(text); error.append(err); }
        else { assert(fields[0] == "R"); let text, err = toml_source::remove(input, path); output.append(text); error.append(err); }
        assert(error.len == 0 || output.len == 0);
        var hex: u8[>..] = []; let digits = "0123456789abcdef";
        for byte in output { hex.push(digits[byte >> 4]); hex.push(digits[byte & 15]); }
        print(if error.len > 0 { "E" } else { "O" }, "\t", hex);
    }
}
