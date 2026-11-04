#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Deterministic public-API resource and hostile-input checks.

The collision generators invert string hashing in the pinned Goose standard
library, exercising both bucket probes and full-key byte comparisons. They need
revalidation when that pin/hash changes;
a work-limit assertion failure must not be silenced by skipping the workload.
"""
import argparse
import json
import random
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HASH_REVISION = "eadca409f68210893f366e60d0c2f0dc29a339be"
MAX_INPUT_BYTES = 1048576
MAX_NODES = 65536
MASK = (1 << 64) - 1
MULTIPLIER = 11400714819323198485
FINAL_MULTIPLIER = 15485907386658061715


def collision_keys(count):
    """Distinct eight-byte ASCII keys with root key_hash & 0x1ffff == 0.

    hash_mix(0) == 0, so root key_hash == string_hash + MULTIPLIER.
    Both odd multiplies and xor-right-shift-32 are invertible modulo 2**64.
    ASCII controls are encoded with legal TOML basic-string escapes by json.dumps.
    """
    inverse_first = pow(MULTIPLIER, -1, 1 << 64)
    inverse_final = pow(FINAL_MULTIPLIER, -1, 1 << 64)
    keys = []
    for i in range(1 << 24):
        target = (i << 17) + ((-MULTIPLIER) & ((1 << 17) - 1))
        value = ((target ^ (target >> 32)) * inverse_final) & MASK
        value ^= value >> 32
        word = ((value * inverse_first) & MASK) ^ ((8 * MULTIPLIER) & MASK)
        raw = word.to_bytes(8, "little")
        if all(c < 128 for c in raw):
            keys.append(raw.decode("ascii"))
            if len(keys) == count:
                return keys
    raise AssertionError("bounded collision search did not produce enough ASCII keys")


def full_collision_keys(count):
    """Distinct 1,040-byte keys sharing a full hash and a 1,024-byte prefix.

    The pinned hash_lanes consumes the fixed prefix in two lanes, combines
    them, and processes one variable word before its final eight-byte word.
    Inverting the final rounds determines a corrective word for a fixed hash.
    Only ASCII variable/corrective words are retained, so every decoded key
    is valid UTF-8 and json.dumps supplies legal TOML basic-string escapes.
    """
    def rotate(value, bits):
        return ((value << bits) | (value >> (64 - bits))) & MASK

    inverse_first = pow(MULTIPLIER, -1, 1 << 64)
    inverse_final = pow(FINAL_MULTIPLIER, -1, 1 << 64)
    target_hash = 0x123456789ABCDEF0
    inverse = ((target_hash ^ (target_hash >> 32)) * inverse_final) & MASK
    inverse ^= inverse >> 32
    inverse = (inverse * inverse_first) & MASK

    prefix = b"A" * 1024
    length = len(prefix) + 16
    first = (length * MULTIPLIER) & MASK
    second = first ^ MULTIPLIER
    for offset in range(0, len(prefix), 16):
        first_word = int.from_bytes(prefix[offset:offset + 8], "little")
        second_word = int.from_bytes(prefix[offset + 8:offset + 16], "little")
        first = rotate(((first ^ first_word) * MULTIPLIER) & MASK, 29)
        second = rotate(((second ^ second_word) * MULTIPLIER) & MASK, 29)
    combined = first ^ rotate(second, 31)

    keys = []
    rng = random.Random(0x700164)
    for _ in range(1 << 20):
        variable = (rng.getrandbits(64) & 0x7F7F7F7F7F7F7F7F).to_bytes(8, "little")
        state = rotate(((combined ^ int.from_bytes(variable, "little")) * MULTIPLIER) & MASK, 29)
        correction = (state ^ inverse).to_bytes(8, "little")
        if not all(c < 128 for c in correction):
            continue
        # Verify the inverted final rounds independently before emitting a key.
        final = ((state ^ int.from_bytes(correction, "little")) * MULTIPLIER) & MASK
        final = ((final ^ (final >> 32)) * FINAL_MULTIPLIER) & MASK
        assert final ^ (final >> 32) == target_hash
        keys.append((prefix + variable + correction).decode("ascii"))
        if len(keys) == count:
            return keys
    raise AssertionError("bounded full-hash collision search did not produce enough ASCII keys")


def main():
    if not __debug__:
        raise SystemExit("test assertions require Python without -O/PYTHONOPTIMIZE")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--decoder", type=Path, default=ROOT / ".build/decoder")
    args = parser.parse_args()
    decoder = str(args.decoder.resolve())
    revision = (ROOT / "GOOSE_REVISION").read_text().strip()
    if revision != HASH_REVISION:
        parser.error("collision generator must be revalidated against the changed GOOSE_REVISION")
    count = 0

    def run(label, source, accepted, error=None):
        nonlocal count
        result = subprocess.run([decoder], input=source, capture_output=True, timeout=5)
        assert not any(marker in result.stderr for marker in (
            b"AddressSanitizer", b"UndefinedBehaviorSanitizer", b"LeakSanitizer", b"runtime error:"
        )), (label, "runtime/sanitizer diagnostic", result.stderr[:1000])
        assert result.returncode in (0, 1), (label, "decoder crashed", result.returncode, result.stderr[:1000])
        if result.returncode == 1:
            assert not result.stdout and result.stderr.startswith(b"toml:"), (label, "non-parser rejection", result.stderr[:1000])
        else:
            assert not result.stderr, (label, "successful parse has diagnostics", result.stderr[:1000])
        if accepted is not None:
            assert result.returncode == (0 if accepted else 1), (label, "unexpected acceptance/rejection", result.stderr[:1000])
        if error is not None:
            assert error in result.stderr, (label, "expected diagnostic absent", result.stderr[:1000])
        count += 1
        if result.returncode == 0:
            return json.loads(result.stdout)
        return None

    keys = collision_keys(5000)
    assert len(set(keys)) == len(keys)
    lines = [(json.dumps(key) + "=1\n").encode("ascii") for key in keys]
    small = run("small real-collision table", b"".join(lines[:200]), True)
    expected_scalar = {"type": "integer", "value": "1"}
    assert small == {key: expected_scalar for key in keys[:200]}
    attack = b"".join(lines)
    assert len(attack) < MAX_INPUT_BYTES and len(keys) + 1 < MAX_NODES
    run("large real-collision table (revalidate pinned hash if this fails)", attack, False, b"work limit exceeded")

    # Full hashes and lengths are equal, so these long common-prefix keys
    # exercise the compared-key-byte budget rather than bucket probes alone.
    full_keys = full_collision_keys(500)
    assert len(set(full_keys)) == len(full_keys) and all(len(key) == 1040 for key in full_keys)
    full_lines = [(json.dumps(key) + f"={i}\n").encode("ascii") for i, key in enumerate(full_keys)]
    small_full = run("small full-hash/common-prefix collision table", b"".join(full_lines[:100]), True)
    assert small_full == {key: {"type": "integer", "value": str(i)} for i, key in enumerate(full_keys[:100])}
    full_attack = b"".join(full_lines)
    assert len(full_attack) < MAX_INPUT_BYTES and len(full_keys) + 1 < MAX_NODES
    run("full-hash/common-prefix compared-byte limit (revalidate pinned hash if this fails)",
        full_attack, False, b"key lookup work limit exceeded")

    # Root + array + one node per scalar: accept exactly the node bound.
    dense = b"v=[" + b"1," * (MAX_NODES - 2) + b"]"
    value = run("dense array at node limit", dense, True)["v"]
    assert len(value) == MAX_NODES - 2 and value[0] == expected_scalar and value[-1] == expected_scalar
    run("dense array over node limit", dense[:-1] + b"1,]", False, b"node limit exceeded")

    # Each inline table adds one table node and one scalar node.
    inline_count = (MAX_NODES - 2) // 2
    inline = b"v=[" + b"{a=1}," * inline_count + b"]"
    value = run("dense inline tables at node limit", inline, True)["v"]
    assert len(value) == inline_count and value[0] == {"a": expected_scalar} and value[-1] == {"a": expected_scalar}

    # Full logical depth and a broad subtree exercise sealing without exceeding limits.
    nested = b"v=" + b"{a=" * 62 + b"[" + b"1," * 64001 + b"]" + b"}" * 62
    value = run("deep inline tables with broad subtree", nested, True)["v"]
    for _ in range(62):
        value = value["a"]
    assert len(value) == 64001

    full_string = b"v='" + b"a" * (MAX_INPUT_BYTES - 4) + b"'"
    assert len(full_string) == MAX_INPUT_BYTES
    value = run("string at input limit", full_string, True)
    assert len(value["v"]["value"]) == MAX_INPUT_BYTES - 4
    run("late malformed string", full_string[:-1] + b"x", False, b"unterminated string")
    run("late malformed trailing data", full_string[:-2] + b"'x", False, b"expected newline")
    run("oversized document", b" " * (MAX_INPUT_BYTES + 1), False, b"input exceeds 1 MiB")

    for bad in [b"\x80", b"\xc0\x80", b"\xed\xa0\x80", b"\xf4\x90\x80\x80", b"\xe2\x82", b"\xff"]:
        run("invalid UTF-8 string", b"v='" + bad + b"'", False, b"invalid UTF-8")
    rng = random.Random(0x5EC017)
    for _ in range(256):
        # This probe asserts termination/no crash; it does not use an acceptance oracle.
        data = bytes(rng.randrange(256) for _ in range(rng.randrange(1024)))
        run("arbitrary-byte termination probe", data, None)
    print(f"{count} hostile-input/resource documents passed, including real hash-collision budget rejection")


if __name__ == "__main__":
    main()
