// SPDX-License-Identifier: Apache-2.0
import toml from "..";
import toml.source.editor;
import std;
import os;
fn main() {
    let argv = args(); var iterations = 100;
    if argv.len > 1 { let n, ok = parse_int(argv[1], 10); assert(ok && n > 0 && n <= 100000); iterations = n; }
    let small = "# notes\n[dependencies]\nold={path='old'} # keep\n[package]\nname='app'\n";
    var large = str("#"); for i in 262144 { large.push('x'); }
    large.append("\n[dependencies]\n");
    for i in 1000 { large.append(str("key", i, "={path='lib'} # keep\n")); }
    large.append("[package]\nname='app'\n");
    let inputs: (const u8[:])[2] = [small, large];
    var checksum = 0;
    for source, index in inputs {
        let key = if index == 0 { "old" } else { "key0" };
        let changed, changed_error = toml_source::put(source, ["dependencies", "new"], "{path='new'}");
        let removed, removed_error = toml_source::remove(source, ["dependencies", key]);
        assert(changed_error.len == 0 && removed_error.len == 0);
        let put_start = clock_ns();
        for i in iterations {
            let output, error = toml_source::put(source, ["dependencies", "new"], "{path='new'}");
            assert(error.len == 0 && output.len == changed.len); checksum += output.len;
        }
        print(if index == 0 { "put_small" } else { "put_large" }, "\t", clock_ns() - put_start, "\t", iterations, "\t", source.len, "\t", changed.len);
        let remove_start = clock_ns();
        for i in iterations {
            let output, error = toml_source::remove(source, ["dependencies", key]);
            assert(error.len == 0 && output.len == removed.len); checksum += output.len;
        }
        print(if index == 0 { "remove_small" } else { "remove_large" }, "\t", clock_ns() - remove_start, "\t", iterations, "\t", source.len, "\t", removed.len);
    }
    print("checksum\t", checksum);
}
