// SPDX-License-Identifier: Apache-2.0
// Complete fresh operations; fixture construction and exact preflight are untimed.
import toml from "../..";
import toml.source.editor;
import std;
import os;
fn invoke(source: const u8[:], part: const u8[:], put: bool) -> u8[>..], u8[>..] {
    if put { return toml_source::put(source, [part], "2"); }
    return toml_source::remove(source, [part]);
}
fn sequence(source: const u8[:], paths: const u8[:][:]) -> u8[>..] {
    var current: u8[>..] = [];
    for part, i in paths {
        let input = if i == 0 { source } else { current };
        let output, error = invoke(input, part, i % 2 == 0);
        assert(error.len == 0);
        if i + 1 == paths.len { return output; }
        current.clear(); current.append(output);
    }
    return current;
}
fn main() {
    let argv = args(); assert(argv.len == 5);
    let batch = argv[1] == "batch"; assert(batch || argv[1] == "sequence");
    let nodes, n_ok = parse_int(argv[2]); let count, c_ok = parse_int(argv[3]);
    let iterations, i_ok = parse_int(argv[4]);
    assert(n_ok && c_ok && i_ok && nodes >= 1 && nodes <= 2048 && count >= 1 && count <= 64 &&
        count <= nodes && iterations >= 1 && iterations <= 100000);
    var source: u8[>..] = []; source.append("# preserved\n");
    var names:  u8[>..] = []; var ends: i64[>..] = [];
    for i in count { format(names, "key", i * (nodes / count)); ends.push(names.len); }
    var paths: (const u8[:])[>..] = []; var start = 0;
    for end in ends { paths.push(names[start..end]); start = end; }
    var expected: u8[>..] = []; expected.append("# preserved\n");
    for i in nodes {
        format(source, "key", i, "=1 # keep\n");
        let target = i / (nodes / count);
        let selected = target < count && i == target * (nodes / count);
        if !selected || target % 2 == 0 { format(expected, "key", i, if selected { "=2" } else { "=1" }); }
        expected.append(" # keep\n");
    }
    var edits: toml_source::Edit[>..] = [];
    for part, i in paths {
        if i % 2 == 0 { edits.push(toml_source::Edit.Put { path: paths[i..i + 1], value: "2" }); }
        else { edits.push(toml_source::Edit.Remove { path: paths[i..i + 1] }); }
    }
    let before, error = toml_source::apply(source, edits);
    assert(error.len == 0 && before == expected && sequence(source, paths) == expected);
    if batch { let out, err = toml_source::apply(source, edits); assert(err.len == 0 && out == expected); }
    else { assert(sequence(source, paths) == expected); }
    var checksum = 0; let begin = clock_ns();
    for i in iterations {
        if batch {
            let output, error = toml_source::apply(source, edits);
            assert(error.len == 0 && output.len == expected.len);
            checksum += output.len + output[0] + output[output.len - 1];
        } else {
            let output = sequence(source, paths); assert(output.len == expected.len);
            checksum += output.len + output[0] + output[output.len - 1];
        }
    }
    let elapsed = clock_ns() - begin;
    let after, after_error = toml_source::apply(source, edits);
    assert(after_error.len == 0 && after == expected && sequence(source, paths) == expected);
    assert(checksum == iterations * (expected.len + expected[0] + expected[expected.len - 1]));
    print(argv[1], "\t", elapsed, "\t", iterations, "\t", source.len, "\t", expected.len, "\t", checksum);
}
