# goose-toml

Parse, edit and write TOML in [Goose](https://github.com/aardappel/goose).
The library owns decoded data and returns errors as strings. It performs no I/O.
Apache-2.0; experimental API.

Use the semantic editor to change values and regenerate TOML, or the source
editor to keep comments and formatting outside the changed text.

## Quick start

Requires Git, Make, CMake 3.27+, a C++20 compiler and Linux development headers.
[Setup and platform details](docs/platforms.md).

```sh
git clone https://github.com/carabistouflette/goose-toml.git
cd goose-toml
git checkout --detach e5e5644c45e78e8eb05999978bb4155ea0bbb180
make setup
.toolchain/goose/build/goose run examples/config.goose
```

The example prints `Server port: 8080`. Alpha.6 uses Goose
`eadca409f68210893f366e60d0c2f0dc29a339be`, pinned in `GOOSE_REVISION`.
Other compiler revisions are not promised compatible.

From another project:

```goose
import toml from "carabistouflette/goose-toml@e5e5644c45e78e8eb05999978bb4155ea0bbb180";
import std;

fn main() {
    var doc = toml::Document { .. };
    let error = toml::parse_into("port = 8080\n", doc);
    if error.len > 0 { print(error); return; }
    let port = toml::find(doc, 0, "port");
    if port >= 0 && doc.nodes[port].kind == toml::Kind.Integer {
        print(doc.nodes[port].integer);
    }
}
```

Pin a full commit. `main` is the development branch; tags are immutable.
This documentation describes alpha.6. Later documentation commits may improve
examples without changing the released library.

## What it supports

- Strict TOML 1.0 by default; pass `toml::Version.V1_1` for TOML 1.1 syntax.
- Tables, dotted/quoted keys, arrays, inline tables, arrays of tables, all TOML
  scalar kinds, signed 64-bit integers and binary64 floats.
- Owned documents with table/array construction, replacement and removal.
- TOML 1.0 output, including conversion of TOML 1.1 spellings.
- Source-preserving single edits and atomic batches. Alpha.5 adds replacement
  of inline values; alpha.6 adds insertion of missing inline members.

There is no automatic application-struct mapping. Semantic writing regenerates
formatting. The source editor cannot remove an individual inline member or
select an array element.

## Limits and ownership

Parsing accepts at most **1 MiB**, **65,536 nodes**, **64 levels** and **128-byte
bare scalar tokens**, with a separate key-work budget. These limits reject some
valid large documents. Semantic writing allows up to 8 MiB of output; the source
editor caps output at 1 MiB. These are not exact memory-allocation limits.

Documents own decoded keys and strings. Accessor views borrow their document;
copy a view before an edit that can invalidate it. After a parsing or semantic
editing error, discard the partial document. Source edits return empty output
on failure and never change the input. Applications own file reads and atomic
file replacement.

## Guides

- [Parsing, lookup and exact limits](docs/api.md)
- [Build, edit and write a document](docs/document.md)
- [Keep source formatting](source/README.md)
- [Platforms and prerequisites](docs/platforms.md)
- [Benchmark status and reproduction](docs/benchmarks.md)
- [Development and tests](docs/development.md)
- [Release history](CHANGELOG.md), [security](SECURITY.md),
  [third-party notices](THIRD_PARTY_NOTICES.md), [contributing](CONTRIBUTING.md)

Historical benchmark records are linked separately. They do not establish a
current cross-language ranking. See [GitHub releases](https://github.com/carabistouflette/goose-toml/releases)
for published versions.
