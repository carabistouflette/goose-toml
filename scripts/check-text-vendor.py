#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Verify immutable goose-text provenance (requires its source repository)."""
import subprocess
import sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
REVISION = "09d5f0c39e50d3270189bd0c6798cd10ab2f0c0d"
source = subprocess.check_output(["git", "-C", sys.argv[1], "show", REVISION + ":text.goose"])
expected = source.replace(b"namespace text;", b"namespace toml_text;")
if (ROOT / "vendor/text.goose").read_bytes() != expected:
    raise SystemExit("Vendored text differs from the documented source plus namespace patch")
license = subprocess.check_output(["git", "-C", sys.argv[1], "show", REVISION + ":LICENSE"])
if (ROOT / "vendor/LICENSE").read_bytes() != license:
    raise SystemExit("Vendored license differs from source")
print("Verified goose-text snapshot " + REVISION)
