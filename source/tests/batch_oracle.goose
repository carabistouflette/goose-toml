// SPDX-License-Identifier: Apache-2.0
import toml from "../..";
import toml.source.editor;
import std;
import os;
struct Range { start: i64, end: i64 }
struct Request { put: bool, value: Range, start: i64, end: i64 }
fn nibble(c: u8) -> u8 {
    if c >= '0' && c <= '9' { return c - '0'; }
    assert(c >= 'a' && c <= 'f'); return c - 'a' + 10;
}
fn decode(input: const u8[:], arena: u8[>..]&) -> Range {
    assert(input.len % 2 == 0); let start = arena.len;
    var at = 0;
    while at < input.len { arena.push(nibble(input[at]) * 16 + nibble(input[at + 1])); at += 2; }
    return Range { start: start, end: arena.len };
}
fn number(input: const u8[:]) -> i64 {
    assert(input.len > 0 && input.len < 5); var value = 0;
    for byte in input { assert(byte >= '0' && byte <= '9'); value = value * 10 + (byte - '0'); }
    return value;
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
        let fields = split(line, '\t'); assert(fields.len >= 3);
        assert(fields[0] == "10" || fields[0] == "11");
        var arena: u8[>..] = []; let source = decode(fields[1], arena);
        let count = number(fields[2]); assert(count <= 65);
        var keys: Range[>..] = []; var requests: Request[>..] = []; var at = 3;
        for i in count {
            assert(at + 2 < fields.len); let put = fields[at] == "P";
            assert(put || fields[at] == "R");
            let value = decode(fields[at + 1], arena); let parts = number(fields[at + 2]);
            at += 3; assert(parts <= 65 && parts <= fields.len - at); let start = keys.len;
            for j in parts { keys.push(decode(fields[at], arena)); at++; }
            requests.push(Request { put: put, value: value, start: start, end: keys.len });
        }
        assert(at == fields.len);
        // Finish each backing arena before retaining any views into it.
        var parts: (const u8[:])[>..] = [];
        for key in keys { parts.push(arena[key.start..key.end]); }
        var edits: toml_source::Edit[>..] = [];
        for request in requests {
            let path = parts[request.start..request.end];
            if request.put { edits.push(toml_source::Edit.Put { path: path, value: arena[request.value.start..request.value.end] }); }
            else { edits.push(toml_source::Edit.Remove { path: path }); }
        }
        let version = if fields[0] == "10" { toml::Version.V1_0 } else { toml::Version.V1_1 };
        let output, error = toml_source::apply(arena[source.start..source.end], edits, version);
        assert(error.len == 0 || output.len == 0);
        print(if error.len == 0 { "O" } else { "E" }, "\t", hex(output), "\t", hex(error));
    }
}
