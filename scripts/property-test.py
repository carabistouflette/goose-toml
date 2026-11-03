#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Deterministic generated-value and mutation checks, independent of toml-test.

Python 3.11+ tomllib is a secondary oracle for this deliberately shared subset;
this does not test TOML datetime/leap-second or overflow policy differences.
"""
import argparse
import json
import math
import random
import subprocess
import tomllib
from pathlib import Path


def untag(value):
    if isinstance(value, list):
        return [untag(v) for v in value]
    if isinstance(value, dict) and set(value) == {"type", "value"}:
        kind, text = value["type"], value["value"]
        if kind == "integer":
            return int(text)
        if kind == "float":
            return float(text)
        if kind == "bool":
            return text == "true"
        if kind == "string":
            return text
        raise AssertionError(f"unexpected generated kind: {kind}")
    return {key: untag(v) for key, v in value.items()}


def equal(a, b):
    if type(a) is not type(b):
        return False
    if isinstance(a, float):
        if math.isnan(a):
            return math.isnan(b)
        return a == b and (a != 0 or math.copysign(1, a) == math.copysign(1, b))
    if isinstance(a, dict):
        return a.keys() == b.keys() and all(equal(a[k], b[k]) for k in a)
    if isinstance(a, list):
        return len(a) == len(b) and all(equal(x, y) for x, y in zip(a, b))
    return a == b


def supported(value):
    # Python accepts arbitrary-precision integers; goose-toml deliberately uses i64.
    if type(value) is int:
        return -(2**63) <= value <= 2**63 - 1
    if isinstance(value, dict):
        return all(supported(v) for v in value.values())
    if isinstance(value, list):
        return all(supported(v) for v in value)
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--decoder", type=Path, default=Path(".build/decoder"))
    parser.add_argument("--cases", type=int, default=1000)
    args = parser.parse_args()
    if not 1 <= args.cases <= 100000:
        parser.error("--cases must be 1..100000")
    rng = random.Random(0x700110)
    decoder = str(args.decoder.resolve())
    checked = 0

    def check(data):
        nonlocal checked
        try:
            expected = tomllib.loads(data.decode("utf-8"))
            if not supported(expected):
                expected = None
        except (UnicodeDecodeError, tomllib.TOMLDecodeError):
            expected = None
        result = subprocess.run([decoder], input=data, capture_output=True, timeout=3)
        assert result.returncode in (0, 1), ("decoder crashed", data, result.stderr)
        if result.returncode == 1:
            assert expected is None, ("unexpected rejection", data, result.stderr)
        else:
            assert expected is not None, ("unexpected acceptance", data, result.stdout)
            decoded = untag(json.loads(result.stdout))
            assert equal(expected, decoded), ("value mismatch", data, expected, decoded)
        checked += 1

    def value(depth=0):
        kind = rng.randrange(5 if depth < 3 else 4)
        if kind == 0:
            n = rng.randint(-(2**63), 2**63 - 1)
            return rng.choice([str(n), f"{n:_}"])
        if kind == 1:
            return rng.choice(["true", "false"])
        if kind == 2:
            return repr(rng.uniform(-1e20, 1e20))
        if kind == 3:
            s = "".join(rng.choices('abc .\t\n\r"\\é😀', k=rng.randrange(30)))
            return json.dumps(s, ensure_ascii=False)
        return "[" + ", ".join(value(depth + 1) for _ in range(rng.randrange(5))) + "]"

    alphabet = b"abc0129_+-=.,[]{}# '\"\\\n\r\t\x00\x7f\xff"
    for _ in range(args.cases):
        lines = [f'{json.dumps("key." + str(i))} = {value()}' for i in range(rng.randrange(1, 10))]
        data = ("\n".join(lines) + "\n").encode()
        check(data)
        mutated = bytearray(data)
        for _ in range(rng.randrange(1, 5)):
            at = rng.randrange(len(mutated) + 1)
            operation = rng.randrange(3)
            if operation == 0:
                mutated[at:at] = bytes([rng.choice(alphabet)])
            elif at < len(mutated):
                if operation == 1:
                    del mutated[at]
                else:
                    mutated[at] = rng.choice(alphabet)
        check(bytes(mutated))
    print(f"{checked} generated/mutated documents passed (seed 0x700110)")


if __name__ == "__main__":
    main()
