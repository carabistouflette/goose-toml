// SPDX-License-Identifier: Apache-2.0
import toml from "..";
import std;
import os;
fn measure(name: u8[:], source: u8[:], iterations: i64) {
    var doc = toml::Document { .. };
    let start = clock_ns();
    var total = 0;
    for i in iterations {
        let error = toml::parse_into(source, doc);
        assert(error.len == 0);
        total += doc.nodes.len;
    }
    print(name, ": ", iterations, " parses, ", source.len, " bytes/input, ", clock_ns() - start, " ns, checksum ", total);
}
fn main() {
    let argv = args();
    var iterations = 10000;
    if argv.len > 1 {
        let n, ok = parse_int(argv[1]);
        if !ok || n < 1 || n > 1000000 { print("iterations must be 1..1000000"); exit(2); }
        iterations = n;
    }
    measure("small config", "title = 'Goose'\n[server]\nport = 8080\nenabled = true\n", iterations);
    var wide: u8[>..] = [];
    for i in 1000 { format(wide, "key", i, " = ", i, "\n"); }
    measure("wide table", wide, max(1, iterations / 100));
    var array = str("values = [");
    for i in 1000 { array.append("1.25,"); }
    array.append("]\n");
    measure("float array", array, max(1, iterations / 100));
    var strings: u8[>..] = [];
    for i in 100 { format(strings, "key", i, " = \"Goose\\n\\u00e9\\U0001f600\"\n"); }
    measure("escaped strings", strings, max(1, iterations / 100));
}
