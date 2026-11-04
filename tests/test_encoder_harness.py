# SPDX-License-Identifier: Apache-2.0
"""Fault injection at the encoder harness's subprocess boundary."""
import contextlib
import io
import json
import runpy
import subprocess
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/encoder-test.py"


class EncoderHarnessTests(unittest.TestCase):
    def invoke(self, string_result=None, rejection_suffix=b""):
        calls = 0

        def encoder(command, *, input, **kwargs):
            nonlocal calls
            calls += 1
            if calls <= 4:
                diagnostic = (b"encoder: numeric token exceeds 128 bytes" if calls <= 2
                              else b"encoder: expected tagged string scalar")
                return subprocess.CompletedProcess(command, 1, b"", diagnostic + b"\n" + rejection_suffix)
            if string_result is not None:
                return string_result
            value = json.loads(input)["v"]["value"]
            output = ("v = " + json.dumps(value, ensure_ascii=False) + "\n").encode("utf-8")
            return subprocess.CompletedProcess(command, 0, output, b"")

        with patch.object(sys, "argv", [str(SCRIPT), "--encoder", "unused"]), \
                patch("subprocess.run", side_effect=encoder), \
                contextlib.redirect_stdout(io.StringIO()):
            runpy.run_path(str(SCRIPT), run_name="__main__")
        self.assertEqual(calls, 9)

    def test_realistic_protocol_results_pass(self):
        self.invoke()

    def test_invalid_or_changed_string_output_fails(self):
        for output in [b"not TOML", b"\xff", b"v = 123.45", b"v = true", b"v = []",
                       b'v = "wrong"', b'other = "-123.45e6"',
                       b'v = "-123.45e6"\nextra = 1']:
            result = subprocess.CompletedProcess([], 0, output, b"")
            with self.subTest(output=output), self.assertRaises(RuntimeError):
                self.invoke(string_result=result)

    def test_success_with_diagnostics_fails(self):
        for diagnostic in [b"warning", b"ERROR: AddressSanitizer", b"runtime error: overflow"]:
            result = subprocess.CompletedProcess([], 0, b'v = "-123.45e6"', diagnostic)
            with self.subTest(diagnostic=diagnostic), self.assertRaises(RuntimeError):
                self.invoke(string_result=result)

    def test_sanitizer_failure_cannot_masquerade_as_resource_rejection(self):
        for diagnostic in [b"AddressSanitizer", b"UndefinedBehaviorSanitizer",
                           b"LeakSanitizer", b"runtime error:"]:
            with self.subTest(diagnostic=diagnostic), self.assertRaises(RuntimeError):
                self.invoke(rejection_suffix=diagnostic)


if __name__ == "__main__":
    unittest.main()
