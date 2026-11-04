#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Bounded protocol regressions for the test-only official encoder adapter."""
import argparse
import json
import subprocess
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--encoder", type=Path, required=True)
    args = parser.parse_args()
    encoder = str(args.encoder.resolve())
    cases = [
        (b'{"v":{"type":"float","value":"1.' + b"0" * 200000 + b'1"}}', b"numeric token exceeds"),
        (b'{"v":{"type":"integer","value":"' + b"1" * 200000 + b'"}}', b"numeric token exceeds"),
        (b'{"v":1.' + b"0" * 200000 + b"1}", b"expected tagged string"),
        (b'{"v":-' + b"1" * 200000 + b"}", b"expected tagged string"),
    ]
    for source, diagnostic in cases:
        result = subprocess.run([encoder], input=source, capture_output=True, timeout=2)
        if result.returncode != 1 or result.stdout or diagnostic not in result.stderr:
            raise RuntimeError(f"wrong resource rejection: status={result.returncode}, stderr={result.stderr[:400]!r}")
    # Numeric-looking text and escaped quotes/backslashes must remain strings.
    for value in ['-123.45e6', '"-12', '\\-12', 'é🪿', '\\"-12']:
        source = json.dumps({"v": {"type": "string", "value": value}}, ensure_ascii=False).encode()
        result = subprocess.run([encoder], input=source, capture_output=True, timeout=2)
        if result.returncode or not result.stdout:
            raise RuntimeError(f"valid protocol string rejected: {result.stderr[:400]!r}")
    print(f"encoder protocol: {len(cases)} resource rejections and 5 string cases passed")


if __name__ == "__main__":
    main()
