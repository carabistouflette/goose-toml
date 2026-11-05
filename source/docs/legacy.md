# Compatibility profile

## Contract

`legacy_set(source, decoded_path, raw_value)` and
`legacy_remove(source, decoded_path)` expose the compatibility profile for
[goose-toml-edit](https://github.com/carabistouflette/goose-toml-edit).
They return the same owned `(output, error)` pair and are fixed to strict
TOML 1.0. They share the scanner, lookup, subtree selection and splice engine
with `put`/`remove`; the default operations retain their existing policies.

The compatibility reference is companion commit
[`cedb2c3c98affbeb45bd34bc7a6618f5a9b75ad0`](https://github.com/carabistouflette/goose-toml-edit/commit/cedb2c3c98affbeb45bd34bc7a6618f5a9b75ad0).
The profile preserves its output and diagnostic bytes, including these rules:

- Validate the path first, replacement fragment second, original source third.
  Parse only the first fragment value using the literal four-byte `x = `
  wrapper, after validating UTF-8 across the whole fragment. Only spaces/tabs
  may follow the value. Trailing comments/newlines or statements return the strict-suffix diagnostic without parsing that suffix.
  Comments/newlines inside a value remain allowed by the TOML grammar.
- Paths permit 1..64 decoded components and up to 1 MiB combined key bytes.
  Traversing through a scalar, array or inline table fails before checking for
  a child. A genuinely missing prefix short-circuits to missing. Removing an
  entire array of tables remains supported.
- Insert at root byte zero or immediately after the closest explicit ancestor
  header's complete line. Use the first source newline style, or LF. New keys
  use TOML quoting with uppercase control escapes, including `\u007F` for DEL.
- Before encoding each inserted key, reserve two quote bytes plus six bytes
  per decoded byte within the 1 MiB insertion cap, including prior separators.
  This conservative guard can reject a new key whose actual encoding would
  fit; it does not apply when replacing/removing an existing assignment.
- Source/output are capped at 1 MiB each and the replacement at 1 MiB minus
  four wrapper bytes; an empty replacement is rejected. Existing parser limits
  also apply. Even a missing-key removal reparses its independent owned copy.
  Every failure returns empty output and an owned nonempty diagnostic.

The companion obtains the complete result before replacing or clearing its
caller's output, preserving input/output aliasing. This module performs no I/O.
The profile is included in alpha.2 and later releases, including alpha.6.
Alpha.1 does not contain these entry points. Use a full immutable revision.

