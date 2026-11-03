# goose-toml

A pure Goose TOML 1.0 document parser. Apache-2.0. Experimental API; no release yet.

The library owns decoded keys, strings, and validated date/time text. Applications own file and process I/O. The initial API is a document parser; struct mapping and serialization are outside its scope.

## Development

`make setup` builds the exact compiler in `GOOSE_REVISION`. Requires Git, CMake 3.27+, C/C++20 compilers, Make, and libc development headers on Linux. Tests additionally use Python 3.11+. Use `make GOOSE=/path/to/goose check test` with an existing compiler.

Run formatting, checks, in-process and native tests before committing. Changes receive independent correctness and resource-safety review. No benchmark claims without reproducible measurements.
