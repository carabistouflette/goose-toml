// SPDX-License-Identifier: Apache-2.0
// Public-API recovery and destination-reuse regressions.
import toml from "..";
import std;

recursive fn same_tree(a: toml::Document&, ai: i64, b: toml::Document&, bi: i64) {
    let x = a.nodes[ai]; let y = b.nodes[bi];
    assert(x.kind == y.kind && x.count == y.count);
    if x.kind == toml::Kind.Table || x.kind == toml::Kind.Array {
        var ac = x.first; var bc = y.first; var seen = 0;
        while ac >= 0 && bc >= 0 {
            if x.kind == toml::Kind.Table {
                assert(toml::key(a, ac) == toml::key(b, bc));
                assert(toml::find(a, ai, toml::key(a, ac)) == ac);
                assert(toml::find(b, bi, toml::key(b, bc)) == bc);
            }
            same_tree(a, ac, b, bc);
            if a.nodes[ac].next < 0 { assert(ac == x.last && bc == y.last); }
            ac = a.nodes[ac].next; bc = b.nodes[bc].next; seen++;
        }
        assert(ac == -1 && bc == -1 && seen == x.count);
        if seen == 0 { assert(x.last == -1 && y.last == -1); }
    } else if x.kind == toml::Kind.Integer { assert(x.integer == y.integer); }
    else if x.kind == toml::Kind.Boolean { assert(x.boolean == y.boolean); }
    else if x.kind == toml::Kind.Float {
        assert(x.number == y.number || (x.number != x.number && y.number != y.number));
        if x.number == 0.0 { assert(1.0 / x.number == 1.0 / y.number); }
    } else { assert(toml::text(a, ai) == toml::text(b, bi)); }
    if x.kind != toml::Kind.Table { assert(toml::find(a, ai, "missing") == -1); }
}
fn success(source: u8[:], reused: toml::Document&) {
    var fresh = toml::Document { .. };
    let error = toml::parse_into(source, fresh);
    if error.len > 0 { print("unexpected rejection: ", error, " (source bytes: ", source.len, ")"); }
    assert(error.len == 0);
    assert(toml::parse_into(source, reused).len == 0);
    assert(reused.nodes.len == fresh.nodes.len);
    same_tree(reused, 0, fresh, 0);
    assert(toml::find(reused, -1, "a") == -1);
    assert(toml::find(reused, reused.nodes.len, "a") == -1);
    assert(toml::find(reused, 0, "never present!") == -1);
}
fn recover(source: u8[:], diagnostic: u8[:], doc: toml::Document&) {
    success("old={nested=[{name='before'},true,1]}\n", doc);
    let error = toml::parse_into(source, doc);
    assert(error.len > 0 && find(error, diagnostic) >= 0);
    // The error is owned independently of the document and subsequent errors.
    let saved = copy(error);
    success("a={child=[1,true,'text',{date=2000-02-29}]}\n", doc);
    success("a='replacement'\n", doc);
    assert(toml::find(doc, 0, "old") == -1);
    assert(toml::find(doc, toml::find(doc, 0, "a"), "child") == -1);
    assert(toml::parse_into("second=", doc).len > 0);
    success("", doc);
    assert(error == saved);
}
fn syntax_recovery(doc: toml::Document&) {
    // Cover lexical, declaration, delimiter, scalar and conversion failures.
    let sources = ["v=", "v=\r", "#\x01", "v='a\nb'", "v='unterminated",
            "v=\"\\q\"", "v=\"\\u12\"", "v=\"\\uGGGG\"", "v=\"\\uD800\"",
            "v=\"\"\"a\\ b\"\"\"", "v='''a''''''", "v=[1,,]", "v={a=1,}",
            "[a]\n[a]", "a=1\na=2", "a=1\na.b=2", "a={}\na.b=1", "a=1\n[[a]]",
            "a..b=1", "v=1 x=2", "v=_1", "v=0b2", "v=01", "v=1.", "v=1e+", "v=1x",
            "v=9223372036854775808", "v=0x8000000000000000", "v=1e9999", "v=2000-02-30"];
    for i in sources.len {
        recover(sources[i], "toml:", doc);
    }
    for bytes in [[0xff, 0, 0, 0], [0xe0, 0x80, 0x80, 0], [0xf4, 0x90, 0x80, 0x80]] {
        var source: u8[>..] = [];
        for c in bytes { if c != 0 { source.push(c as u8); } }
        recover(source, "invalid UTF-8", doc);
    }
}
fn shape_switches(doc: toml::Document&) {
    for round in 3 {
        let sources = ["a=1", "a=-0.0", "a=nan", "a=true", "a='changed'", "a=2000-02-29",
                "a=07:32:00.123", "a=2000-02-29T07:32:00", "a=2000-02-29T07:32:00Z",
                "a=[]", "a={}", "a={b={c=1}}", "a=[{b=[2]},'tail']",
                "[[a]]\nb=1\n[[a]]\nb=2", "[a.b]\nc=3", "\"a.b\"=4\n''=5", ""];
        for i in sources.len {
            success(sources[i], doc);
        }
    }
}
fn size_and_limit_recovery(doc: toml::Document&) {
    var large = str("a='");
    for i in 1048572 { large.push('x'); }
    large.push('\'');
    var dense = str("a=[");
    for i in 65534 { dense.append("1,"); }
    dense.push(']');
    var wide: u8[>..] = [];
    for i in 2049 { format(wide, "k", i, "={v=", i, "}\n"); }
    for round in 2 {
        success(large, doc); success("a=1", doc);
        success(dense, doc); success("a={b=2}", doc);
        success(wide, doc); success("", doc);
    }
    large.push(' '); recover(large, "input exceeds", doc);
    large.pop(); large.pop(); recover(large, "unterminated string", doc);
    dense.pop(); dense.append("1,]"); recover(dense, "node limit", doc);
    var nested = str("a=");
    for i in 64 { nested.push('['); }
    nested.push('1');
    for i in 64 { nested.push(']'); }
    recover(nested, "nesting limit", doc);
    var dotted: u8[>..] = [];
    for i in 65 { if i > 0 { dotted.push('.'); } dotted.push('a'); }
    dotted.append("=1"); recover(dotted, "key path limit", doc);
    var token = str("a=");
    for i in 129 { token.push('1'); }
    recover(token, "scalar token exceeds", doc);
}
// Same pinned-hash inversion as scripts/security-test.py. This produces actual
// decoded ASCII keys sharing a bucket at every possible table size, without I/O
// or a large checked-in fixture. Revalidate if GOOSE_REVISION changes.
fn collision_recovery(doc: toml::Document&) {
    let multiplier:    u64 = 11400714819323198485;
    let inverse_first: u64 = 17428512612931826493;
    let inverse_final: u64 = 14982988110149298331;
    var source: u8[>..] = [];
    var raw:    u8[8]   = [0, 0, 0, 0, 0, 0, 0, 0];
    var count = 0;
    for candidate in 16777216 {
        let target = ((candidate as u64) << 17) + ((0 - multiplier) & 0x1ffff);
        var value = (target ^ (target >> 32)) * inverse_final;
        value ^= value >> 32;
        let word = (value * inverse_first) ^ (8 * multiplier);
        var ascii = true;
        for j in 8 {
            let c = ((word >> (j * 8)) & 255) as u8;
            raw[j] = c;
            if c >= 128 { ascii = false; }
        }
        if !ascii { continue; }
        assert((hash_combine(hash(0), hash(raw)) & 0x1ffff) == 0);
        source.push('"');
        for c in raw {
            source.append("\\u00");
            source.push("0123456789abcdef"[(c >> 4) as i64]);
            source.push("0123456789abcdef"[(c & 15) as i64]);
        }
        source.append("\"=1\n"); count++;
        if count == 200 { success(source, doc); }
        if count == 5000 { break; }
    }
    assert(count == 5000);
    recover(source, "key lookup work limit exceeded", doc);
    // One ordinary entry changes the budget crossing to insertion, after a
    // node has already been linked. Both partial states must be reusable.
    let insertion_attack = str("ordinary0=1\n", source);
    recover(insertion_attack, "key index work limit exceeded", doc);
}
fn main() {
    var doc = toml::Document { .. };
    syntax_recovery(doc); shape_switches(doc); size_and_limit_recovery(doc); collision_recovery(doc);
    print("lifecycle tests passed");
}
