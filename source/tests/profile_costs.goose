// SPDX-License-Identifier: Apache-2.0
// Follow-up measurement fixture; no timing thresholds or library instrumentation.
import toml from "../..";
import toml.source.editor;
import std;
import os;
fn invoke(source: const u8[:], path: const u8[:][:], legacy: bool, removing: bool) -> u8[>..], u8[>..] {
    if legacy {
        if removing { return toml_source::legacy_remove(source, path); }
        return toml_source::legacy_set(source, path, "2");
    }
    if removing { return toml_source::remove(source, path); }
    return toml_source::put(source, path, "2");
}
fn main() {
    let argv = args();
    assert(argv.len == 8); // profile operation padding nodes target iterations warmups
    assert(argv[1] == "source" || argv[1] == "legacy");
    assert(argv[2] == "set" || argv[2] == "remove");
    let padding, p_ok = parse_int(argv[3]); let nodes, n_ok = parse_int(argv[4]);
    let target, t_ok = parse_int(argv[5]); let iterations, i_ok = parse_int(argv[6]);
    let warmups, w_ok = parse_int(argv[7]);
    assert(p_ok && n_ok && t_ok && i_ok && w_ok);
    assert(padding >= 0 && padding <= 1000000 && nodes >= 1 && nodes <= 10000);
    assert(target >= -1 && target < nodes && iterations >= 1 && iterations <= 100000);
    assert(warmups >= 0 && warmups <= 10000);
    let legacy = argv[1] == "legacy"; let removing = argv[2] == "remove";
    var source: u8[>..] = []; var expected: u8[>..] = [];
    if legacy && !removing && target < 0 { expected.append("\"absent\" = 2\n"); }
    source.append("# lead\n"); expected.append("# lead\n");
    if padding > 0 {
        source.push('#'); expected.push('#');
        for i in padding { source.push(' '); expected.push(' '); }
        source.push('\n'); expected.push('\n');
    }
    for i in nodes {
        source.append("key"); format(source, i); source.append("=1 # keep\n");
        if i != target || !removing {
            expected.append("key"); format(expected, i);
            expected.append(if i == target { "=2" } else { "=1" });
        }
        expected.append(" # keep\n");
    }
    if !legacy && !removing && target < 0 { expected.append("\"absent\" = 2\n"); }
    assert(source.len <= 1048576 && expected.len <= 1048576);
    var key: u8[>..] = [];
    if target < 0 { key.append("absent"); } else { key.append("key"); format(key, target); }
    let path: (const u8[:])[1] = [key];
    // Full preflight always runs; warmups counts additional calls, not cold use.
    // Full bytes checked before/after timing; loops use constant-cost checks.
    let before, before_error = invoke(source, path, legacy, removing);
    assert(before_error.len == 0 && before == expected);
    let per_call = expected.len + expected[0] + expected[expected.len - 1];
    for i in warmups {
        let output, error = invoke(source, path, legacy, removing);
        assert(error.len == 0 && output.len == expected.len);
    }
    var checksum: i64 = 0;
    let start = clock_ns();
    for i in iterations {
        let output, error = invoke(source, path, legacy, removing);
        assert(error.len == 0 && output.len == expected.len);
        checksum += output.len + output[0] + output[output.len - 1];
    }
    let elapsed = clock_ns() - start;
    let after, after_error = invoke(source, path, legacy, removing);
    assert(after_error.len == 0 && after == expected && checksum == iterations * per_call);
    print(argv[1], "\t", argv[2], "\t", padding, "\t", nodes, "\t", target, "\t", iterations,
        "\t", warmups, "\t", source.len, "\t", expected.len, "\t", elapsed, "\t", checksum);
}
