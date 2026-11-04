#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Independent raw-i64/binary64 writer oracle using Python 3.11+ tomllib.

The Goose adapter constructs Float or Integer directly from high/low raw words,
serializes it, and returns TOML. It never parses decimal floats or TOML. Python
checks the resulting scalar is a float and packs it back to the original bits;
NaN sign/payload identity is intentionally unspecified and only isnan is checked.
Signed zero, finite values and infinities require exact IEEE equality.

A deterministic raw-bit sample supplements biased mantissa/exponent boundaries,
near-zero values, common decimal fractions and the pinned formatter's fast/fallback
transition regions. This is a correctness campaign, not a throughput benchmark.
Batch input, record size, process duration and total requested cases are bounded.
Any crash, nonzero exit, runtime diagnostics, timeout or framing violation fails;
there is no ordinary parse-rejection result that could conceal a runtime failure.
Explicit checks remain active under Python -O.
"""
import argparse
import math
import random
import struct
import subprocess
import sys
import tomllib
from pathlib import Path

SEED = 0xA525420
MASK64 = (1 << 64) - 1


class WriterScalarFailure(Exception):
    pass


def require(condition, message):
    if not condition:
        raise WriterScalarFailure(message)


def float_bits(value):
    return int.from_bytes(struct.pack(">d", value), "big")


def from_bits(bits):
    return struct.unpack(">d", bits.to_bytes(8, "big"))[0]


def random_bits(count):
    rng = random.Random(SEED)
    for _ in range(count):
        yield rng.getrandbits(64)


def biased_bits():
    values = set()

    def around(bits, distance=2):
        for offset in range(-distance, distance + 1):
            candidate = bits + offset
            if 0 <= candidate <= MASK64:
                values.add(candidate)
                values.add(candidate ^ (1 << 63))

    # Walk every encoded exponent, including subnormal and nonfinite encodings,
    # across mantissa endpoints, ties, and decimal-sensitive significands.
    mantissas = [0, 1, 2, 3, (1 << 51) - 1, 1 << 51,
                 (1 << 51) + 1, (1 << 52) - 3, (1 << 52) - 2, (1 << 52) - 1,
                 0x5555555555555, 0xAAAAAAAAAAAAA]
    for exponent in range(2048):
        for mantissa in mantissas:
            around((exponent << 52) | mantissa, distance=0)

    # Dense small-subnormal sampling plus endpoints and nonfinite boundaries.
    for bits in range(4096):
        around(bits, distance=0)
    for bits in [0x000FFFFFFFFFFFFF, 0x0010000000000000,
                 0x7FEFFFFFFFFFFFFF, 0x7FF0000000000000,
                 0x7FF0000000000001, 0x7FF8000000000000]:
        around(bits, distance=16)

    # The pinned Ryu-style fast path covers a central magnitude window;
    # decimal powers and powers of two probe both sides and the fallback.
    for exponent in range(-324, 309):
        around(float_bits(float(f"1e{exponent}")))
    for exponent in range(-1074, 1024):
        around(float_bits(math.ldexp(1.0, exponent)))
    for value in [1e-10, 1e-9, 1e-6, 1e-5, 1e-4, 1e-3,
                  1e15, 1e16, float(2**51), float(2**52), float(2**53)]:
        around(float_bits(value), distance=32)
    for numerator in range(1, 101):
        for denominator in [3, 7, 10, 100, 1000]:
            around(float_bits(numerator / denominator))
    return iter(sorted(values))


def check_frame(bits, frame, integer=False):
    label = f"bits={bits:016x}, response={frame!r}"
    require(frame.startswith(b"T\t") and frame.count(b"\t") == 1, "invalid response frame: " + label)
    payload = frame[2:]
    require(0 < len(payload) <= 64 and b"\r" not in payload, "invalid document frame size: " + label)
    try:
        document = tomllib.loads(payload.decode("ascii"))
    except (UnicodeDecodeError, tomllib.TOMLDecodeError) as error:
        raise WriterScalarFailure("invalid serialized TOML: " + label) from error
    require(set(document) == {"v"}, "wrong serialized document keys: " + label)
    value = document["v"]
    if integer:
        expected_integer = bits if bits < 1 << 63 else bits - (1 << 64)
        require(type(value) is int and value == expected_integer, "writer changed integer kind/value: " + label)
        return
    require(type(value) is float, "writer changed Float to another TOML kind: " + label)
    expected = from_bits(bits)
    if math.isnan(expected):
        require(math.isnan(value), "writer changed NaN: " + label)
    else:
        require(float_bits(value) == bits, "writer changed binary64 value or zero sign: " + label)


def run_batch(runner, cases, timeout, integer=False):
    source = "".join(f"{bits >> 32:08x}\t{bits & 0xFFFFFFFF:08x}\n" for bits in cases).encode("ascii")
    require(len(source) <= 180000, "input batch exceeds adapter cap")
    try:
        result = subprocess.run([runner, "--integer"] if integer else [runner], input=source, capture_output=True, timeout=timeout)
    except subprocess.TimeoutExpired as error:
        raise WriterScalarFailure(f"writer adapter timed out after {timeout}s ({len(cases)} records)") from error
    except OSError as error:
        raise WriterScalarFailure(f"cannot run writer adapter: {error}") from error
    require(result.returncode == 0, f"writer adapter process failure ({result.returncode}): {result.stderr[:4000]!r}")
    require(not result.stderr, f"writer adapter runtime diagnostics: {result.stderr[:4000]!r}")
    require(len(result.stdout) <= len(cases) * 67, "writer adapter output exceeds bounded record budget")
    require(result.stdout.endswith(b"\n"), "writer adapter response lacks final newline")
    frames = result.stdout.split(b"\n")[:-1]
    require(len(frames) == len(cases), f"writer adapter returned {len(frames)} frames for {len(cases)} records")
    for bits, frame in zip(cases, frames):
        check_frame(bits, frame, integer)


def campaign(runner, cases, batch_size, timeout, integer=False):
    batch = []
    checked = 0
    for bits in cases:
        batch.append(bits)
        if len(batch) == batch_size:
            run_batch(runner, batch, timeout, integer)
            checked += len(batch)
            batch = []
    if batch:
        run_batch(runner, batch, timeout, integer)
        checked += len(batch)
    return checked


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--integer", action="store_true", help="check signed i64 instead of binary64")
    parser.add_argument("--runner", type=Path, default=Path(".build/writer-scalars"))
    parser.add_argument("--random-cases", type=int, default=100000)
    parser.add_argument("--batch-size", type=int, default=5000)
    parser.add_argument("--timeout", type=float, default=30, help="maximum seconds per batch")
    args = parser.parse_args()
    if not 100000 <= args.random_cases <= 1000000:
        parser.error("--random-cases must be 100000..1000000")
    if not 1 <= args.batch_size <= 10000:
        parser.error("--batch-size must be 1..10000")
    if not math.isfinite(args.timeout) or not 0 < args.timeout <= 300:
        parser.error("--timeout must be finite and in (0, 300]")
    runner = str(args.runner.resolve())
    raw = campaign(runner, random_bits(args.random_cases), args.batch_size, args.timeout, args.integer)
    print(f"{raw} independent random 64-bit writer cases passed (seed {SEED:#x})", flush=True)
    if args.integer:
        boundaries = {0, 1, (1 << 63) - 1, 1 << 63, (1 << 64) - 1}
        for exponent in range(20):
            for offset in range(-4, 5):
                value = 10 ** exponent + offset
                if 0 <= value < 1 << 63:
                    boundaries.add(value)
                    boundaries.add((-value) & MASK64)
        cases = sorted(boundaries)
    else:
        cases = biased_bits()
    biased = campaign(runner, cases, args.batch_size, args.timeout, args.integer)
    print(f"{biased} biased writer boundary cases passed", flush=True)
    print(f"{raw + biased} raw-bits -> TOML -> Python writer cases passed")


if __name__ == "__main__":
    try:
        main()
    except WriterScalarFailure as error:
        print(f"writer scalar test failed: {error}", file=sys.stderr)
        raise SystemExit(1)
