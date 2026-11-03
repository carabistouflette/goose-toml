// SPDX-License-Identifier: Apache-2.0
import toml from "..";
import std;
fn main() {
    var doc = toml::Document { .. };
    let error = toml::parse_into("title = 'Goose'\n[server]\nport = 8080\n", doc);
    if error.len > 0 { print(error); return; }
    let server = toml::find(doc, 0, "server");
    let port = toml::find(doc, server, "port");
    assert(port >= 0 && doc.nodes[port].kind == toml::Kind.Integer);
    print("Server port: ", doc.nodes[port].integer);
}
