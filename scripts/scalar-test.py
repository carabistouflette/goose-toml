#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Batched scalar grammar and exact-value checks through the public Goose API.

Requires Python 3.11+ tomllib and a compiled tests/scalars.goose adapter.
Each token becomes an independent `v=TOKEN` document; the adapter reuses its
Document after both successful and rejected parses. Batches bound input/output
memory and process startup costs. Runtime diagnostics, abnormal exits, timeouts,
and malformed/missing/extra response frames fail independently of parse errors.

The secondary oracle checks acceptance, scalar kind, integer/boolean value, and
float.hex() equality (including signed zero). NaN encoding/sign is unspecified,
so NaNs compare with isnan. Python's arbitrary-precision integers are restricted
to i64; decimal overflow is rejected while explicit inf/nan remains valid. Tokens
longer than 128 ASCII bytes are rejected per goose-toml's documented scalar cap.
Datetimes and strings are covered by other suites, not this numeric campaign.
"""
import argparse
import decimal
import itertools
import math
import random
import re
import subprocess
import sys
import time
import tomllib
from pathlib import Path

SEED = 0x850AC24
BATCH_SIZE = 5000
FLOAT_FRAME = re.compile(r"(?:-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?|-?inf|nan)")


class ScalarFailure(Exception):
    pass


def require(condition, message):
    # Explicit checks keep this validation active under Python -O.
    if not condition:
        raise ScalarFailure(message)


def oracle(token):
    try:
        value = tomllib.loads("v=" + token)["v"]
    except (tomllib.TOMLDecodeError, KeyError):
        return "E", None
    if len(token) > 128:  # All generated tokens are ASCII.
        return "E", None
    if type(value) is int:
        return ("I", value) if -(2**63) <= value < 2**63 else ("E", None)
    if type(value) is float:
        if math.isinf(value) and token.lstrip("+-") != "inf":
            return "E", None
        return "F", value
    if type(value) is bool:
        return "B", value
    raise ScalarFailure(f"generator produced an out-of-scope oracle value: {token!r}")


def check_frame(token, frame):
    kind, expected = oracle(token)
    context = f"token={token!r}, response={frame!r}, expected={kind}:{expected!r}"
    if kind == "E":
        require(frame == "E", "expected ordinary parse rejection: " + context)
        return
    parts = frame.split("\t")
    require(len(parts) == 2 and parts[0] == kind, "wrong scalar kind/frame: " + context)
    payload = parts[1]
    if kind == "I":
        require(payload == str(expected), "wrong integer value: " + context)
    elif kind == "B":
        require(payload == ("true" if expected else "false"), "wrong boolean value: " + context)
    else:
        require(FLOAT_FRAME.fullmatch(payload) is not None, "invalid float frame: " + context)
        value = float(payload)
        same = math.isnan(value) and math.isnan(expected) if math.isnan(expected) else value.hex() == expected.hex()
        require(same, "wrong binary64 value or zero sign: " + context)


def run_batch(runner, tokens, timeout):
    source = ("\n".join(tokens) + "\n").encode("ascii")
    try:
        result = subprocess.run([runner], input=source, capture_output=True, timeout=timeout)
    except subprocess.TimeoutExpired as error:
        raise ScalarFailure(f"scalar adapter timed out after {timeout}s ({len(tokens)} records)") from error
    except OSError as error:
        raise ScalarFailure(f"cannot run scalar adapter: {error}") from error
    require(result.returncode == 0, f"scalar adapter process failure ({result.returncode}): {result.stderr[:4000]!r}")
    require(not result.stderr, f"scalar adapter runtime diagnostics: {result.stderr[:4000]!r}")
    require(result.stdout.endswith(b"\n"), "scalar adapter response lacks final newline")
    frames = result.stdout.split(b"\n")[:-1]
    require(len(frames) == len(tokens), f"scalar adapter returned {len(frames)} frames for {len(tokens)} records")
    for token, raw in zip(tokens, frames):
        try:
            frame = raw.decode("ascii")
        except UnicodeDecodeError as error:
            raise ScalarFailure(f"non-ASCII scalar response: {raw!r}") from error
        check_frame(token, frame)


def short_grammar():
    # Exhaust all strings of length 0..5 over representative radix/sign/decimal
    # characters. Other radix digits and longer forms appear in structured cases.
    for length in range(6):
        for chars in itertools.product("01+-.eE_xbof", repeat=length):
            yield "".join(chars)


def structured_boundaries():
    tokens = {"true", "false", "inf", "+inf", "-inf", "nan", "+nan", "-nan"}
    boundaries = [0, 1, 2, 7, 8, 9, 10, 15, 16, 17, 127, 128, 255, 256,
                  2**31 - 1, 2**31, 2**32 - 1, 2**32, 2**53 - 1, 2**53,
                  2**63 - 1, 2**63, 2**63 + 1]
    for number in boundaries:
        for spelling in [str(number), hex(number), oct(number), bin(number)]:
            for sign in ["", "+", "-"]:
                token = sign + spelling
                tokens.add(token)
                for at in range(len(token) + 1):
                    for inserted in ["_", "+", "-", ".", "e", "E", "0", "7", "8", "9"]:
                        tokens.add(token[:at] + inserted + token[at:])
    for sign, whole, fraction, letter, esign, exponent in itertools.product(
            ["", "+", "-"], ["0", "1", "12", "123", "1234"],
            ["", ".0", ".01", ".1_2"], ["e", "E"], ["", "+", "-"],
            ["0", "1", "9", "99", "309", "9999", "0_1"]):
        tokens.add(sign + whole + fraction + letter + esign + exponent)
    return iter(sorted(tokens))


def scalar_length_boundaries():
    rng = random.Random(SEED)
    tokens = set()
    for length in range(126, 131):
        for sign in ["", "+", "-"]:
            for exponent in ["e0", "e-999999", "e+999999999999999999999999999999", "e-324", "e308", "e-20"]:
                count = length - len(sign) - len(exponent) - 2
                for whole in ["0", "1", "9"]:
                    for fraction in ["0" * count, "9" * count, "".join(rng.choices("0123456789", k=count))]:
                        tokens.add(sign + whole + "." + fraction + exponent)
            for prefix in ["0x", "0o", "0b"]:
                for last in ["0", "1", "7", "8", "f"]:
                    tokens.add(sign + prefix + "0" * (length - len(sign) - len(prefix) - 1) + last)
    for _ in range(10000):
        sign = rng.choice(["", "+", "-"])
        whole = str(rng.randrange(10))
        exponent = rng.choice(["e", "E"]) + str(rng.randint(-450, 450))
        length = rng.randrange(110, 131)
        count = length - len(sign) - len(exponent) - 2
        tokens.add(sign + whole + "." + "".join(rng.choices("0123456789", k=count)) + exponent)
    return iter(sorted(tokens))


def rounding_boundaries():
    tokens = set()
    # Enough precision to form exact midpoints even between adjacent subnormals;
    # then round their decimal spellings to several lengths inside the token cap.
    with decimal.localcontext() as context:
        context.prec = 2000
        for exponent in range(-1074, 1024, 7):
            for mantissa in [1.0, 1.25, 1.5, 1.75]:
                value = math.ldexp(mantissa, exponent)
                successor = math.nextafter(value, math.inf)
                if not math.isfinite(successor):
                    continue
                midpoint = (decimal.Decimal.from_float(value) + decimal.Decimal.from_float(successor)) / 2
                for precision in [17, 32, 64, 110, 118]:
                    quantum = decimal.Decimal(1).scaleb(midpoint.adjusted() - precision)
                    for direction in [-1, 0, 1]:
                        token = format(midpoint + direction * quantum, f".{precision}E")
                        if len(token) <= 128:
                            tokens.add(token)
                        if len(token) + 1 <= 128:
                            tokens.add("-" + token)
    for sign, digits, exponent, letter in itertools.product(
            ["", "+", "-"], [1, 2, 19, 20, 100, 110],
            ["0", "-0", "+0", "9999999999", "-9999999999", "308", "-324"], ["e", "E"]):
        for mantissa in ["0." + "0" * digits, "1." + "0" * digits, "9." + "9" * digits]:
            token = sign + mantissa + letter + exponent
            if len(token) <= 128:
                tokens.add(token)
    return iter(sorted(tokens))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runner", type=Path, default=Path(".build/scalars"))
    parser.add_argument("--batch-size", type=int, default=BATCH_SIZE)
    parser.add_argument("--timeout", type=float, default=20, help="maximum seconds per batch")
    args = parser.parse_args()
    if not 1 <= args.batch_size <= 10000:
        parser.error("--batch-size must be 1..10000")
    if not math.isfinite(args.timeout) or not 0 < args.timeout <= 300:
        parser.error("--timeout must be finite and in (0, 300]")
    runner = str(args.runner.resolve())
    start = time.monotonic()
    total = 0
    campaigns = [short_grammar, structured_boundaries, scalar_length_boundaries, rounding_boundaries]
    for campaign in campaigns:
        count = 0
        tokens = []
        for token in campaign():
            tokens.append(token)
            if len(tokens) == args.batch_size:
                run_batch(runner, tokens, args.timeout)
                count += len(tokens)
                tokens = []
        if tokens:
            run_batch(runner, tokens, args.timeout)
            count += len(tokens)
        total += count
        print(f"{campaign.__name__}: {count} passed", flush=True)
    print(f"{total} scalar cases passed in {time.monotonic() - start:.2f}s (seed {SEED:#x})")


if __name__ == "__main__":
    try:
        main()
    except ScalarFailure as error:
        print(f"scalar test failed: {error}", file=sys.stderr)
        raise SystemExit(1)
