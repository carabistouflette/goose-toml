// SPDX-License-Identifier: Apache-2.0
// Independent writer adapter: raw IEEE-754 bits -> Input.Float -> serialized TOML.
// Input is high/low 32-bit words, each eight hex digits separated by TAB.
// Output is T<TAB>the one-line TOML document, one newline-terminated record each.
// This adapter never invokes Goose's TOML or decimal-float parser.
import toml from "..";
import std;
import binary;
import os;

fn bad_frame() { write_stderr("writer scalar adapter: invalid input frame\n"); exit(2); }
fn word(text: const u8[:]) -> i64 {
    if text.len != 8 { bad_frame(); return 0; }
    for c in text {
        if !((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')) { bad_frame(); return 0; }
    }
    let value, ok = parse_int(text, 16);
    if !ok || value < 0 || value > 4294967295 { bad_frame(); return 0; }
    return value;
}
fn main() {
    var input: u8[>..] = []; read_stdin(input);
    if input.len == 0 || input.len > 180000 || input[input.len - 1] != '\n' { bad_frame(); return; }
    let lines = split(input, '\n');
    var doc = toml::Document { .. }; var output: u8[>..] = [];
    for line, i in lines {
        if i + 1 == lines.len { break; }
        if line.len != 17 || line[8] != '\t' { bad_frame(); return; }
        let high = word(line[..8]); let low = word(line[9..]);
        let bytes: u8[8] = [
            (low & 255) as u8, ((low >> 8) & 255) as u8, ((low >> 16) & 255) as u8, (low >> 24) as u8,
            (high & 255) as u8, ((high >> 8) & 255) as u8, ((high >> 16) & 255) as u8, (high >> 24) as u8,
        ];
        let value, ok = binary::read_f64le(bytes, 0); assert(ok);
        toml::init(doc);
        let id, put_error = toml::put(doc, 0, "v", toml::Input.Float { value: value });
        assert(put_error.len == 0 && id > 0);
        let source, error = toml::serialize(doc);
        if error.len > 0 { write_stderr(error); write_stderr("\n"); exit(3); }
        // A binary64 scalar needs only a small constant-size decimal spelling.
        // Also prevent accidental extra record delimiters from passing.
        assert(source.len > 0 && source.len <= 64 && source[source.len - 1] == '\n');
        var newlines = 0; for c in source { if c == '\n' { newlines++; } }
        assert(newlines == 1);
        output.append("T\t"); output.append(source);
    }
    write_stdout(output);
}
