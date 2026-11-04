# SPDX-License-Identifier: Apache-2.0
"""Regression tests for the independent-oracle harness, not parser internals."""
import contextlib
import io
import runpy
import subprocess
import sys
import tomllib
import unittest
from pathlib import Path
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/property-test.py"


class PropertyHarnessTests(unittest.TestCase):
    def invoke_rejection(self, stderr, stdout=b""):
        result = subprocess.CompletedProcess([], 1, stdout=stdout, stderr=stderr)
        malformed = tomllib.TOMLDecodeError("synthetic malformed input", "", 0)
        with patch.object(sys, "argv", [str(SCRIPT), "--cases", "1"]), \
                patch("tomllib.loads", side_effect=malformed), \
                patch("subprocess.run", return_value=result) as decoder, \
                contextlib.redirect_stdout(io.StringIO()):
            runpy.run_path(str(SCRIPT), run_name="__main__")
            self.assertEqual(decoder.call_count, 2)

    def test_type_value_tables_are_not_scalar_tags(self):
        untag = runpy.run_path(str(SCRIPT))["untag"]
        table = {"type": {"type": "integer", "value": "1"},
                 "value": [{"type": "string", "value": "data"}]}
        self.assertEqual(untag({"nested": table}), {"nested": {"type": 1, "value": ["data"]}})
        self.assertEqual(untag({"type": "string", "value": "data"}), "data")

    def test_crash_exit_cannot_masquerade_as_parse_rejection(self):
        for diagnostic in [b"goose runtime error: assert failed\n",
                           b"toml: invalid scalar\nERROR: AddressSanitizer: out-of-bounds\n",
                           b"toml: invalid scalar\nUndefinedBehaviorSanitizer: overflow\n"]:
            with self.subTest(diagnostic=diagnostic), self.assertRaisesRegex(AssertionError, "runtime/sanitizer diagnostic"):
                self.invoke_rejection(diagnostic)

    def test_rejections_need_parser_diagnostic_and_empty_stdout(self):
        for diagnostic, output in [(b"", b""), (b"unrelated failure\n", b""),
                                   (b"toml: invalid scalar\n", b"partial output")]:
            with self.subTest(diagnostic=diagnostic, output=output), self.assertRaisesRegex(AssertionError, "non-parser rejection"):
                self.invoke_rejection(diagnostic, output)

    def test_normal_parser_rejection_is_still_accepted(self):
        self.invoke_rejection(b"toml: invalid scalar at byte 2\n")


if __name__ == "__main__":
    unittest.main()
