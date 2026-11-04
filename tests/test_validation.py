# SPDX-License-Identifier: Apache-2.0
"""Regression tests for the independent-oracle harness, not parser internals."""
import contextlib
import io
import runpy
import subprocess
import struct
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


class ScalarBitHarnessTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.scalar = runpy.run_path(str(SCRIPT.with_name("scalar-test.py")))

    def check(self, token, value):
        self.scalar["check_frame"](token, "F\t" + struct.pack("=d", value).hex())

    def test_raw_finite_bits_and_zero_sign(self):
        self.check("1.0", 1.0)
        self.check("-0.0", -0.0)
        for token, wrong in [("1.0", 1.0000000000000002), ("-0.0", 0.0), ("inf", -float("inf"))]:
            with self.subTest(token=token), self.assertRaises(self.scalar["ScalarFailure"]):
                self.check(token, wrong)

    def test_nan_policy_accepts_payloads_but_not_infinity(self):
        for bits in [0x7ff0000000000001, 0xfff8000000000042]:
            self.scalar["check_frame"]("nan", "F\t" + bits.to_bytes(8, sys.byteorder).hex())
        with self.assertRaises(self.scalar["ScalarFailure"]):
            self.check("nan", float("inf"))

    def test_wrong_or_truncated_bit_frames_fail(self):
        for frame in ["F\t1.0", "F\t00000000", "F\tfffffffffffffffff", "F\t000000000000000G"]:
            with self.subTest(frame=frame), self.assertRaises(self.scalar["ScalarFailure"]):
                self.scalar["check_frame"]("1.0", frame)


class WriterBitHarnessTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.writer = runpy.run_path(str(SCRIPT.with_name("writer-scalar-test.py")))

    def test_wrong_value_type_and_zero_sign_fail(self):
        for bits, frame in [(0x3ff0000000000000, b'T\t"v" = 1'),
                            (0x8000000000000000, b'T\t"v" = 0.0'),
                            (0x3ff0000000000000, b'T\t"v" = 2.0'),
                            (0x7ff8000000000001, b'T\t"v" = inf'),
                            (0x3ff0000000000000, b'T\t"v" = 1.0\textra')]:
            with self.subTest(frame=frame), self.assertRaises(self.writer["WriterScalarFailure"]):
                self.writer["check_frame"](bits, frame)
        self.writer["check_frame"](0x8000000000000000, b'T\t"v" = -0.0')
        self.writer["check_frame"](0x7ff8000000000001, b'T\t"v" = -nan')

    def test_process_failures_and_bad_framing_are_not_success(self):
        for code, output, error in [(1, b'T\t"v" = 1.0\n', b""),
                                    (-6, b"", b"assert failed"),
                                    (0, b'T\t"v" = 1.0\n', b"runtime error"),
                                    (0, b'T\t"v" = 1.0', b""),
                                    (0, b'T\t"v" = 1.0\nT\t"v" = 1.0\n', b"")]:
            result = subprocess.CompletedProcess([], code, stdout=output, stderr=error)
            with self.subTest(code=code, output=output), patch("subprocess.run", return_value=result), \
                    self.assertRaises(self.writer["WriterScalarFailure"]):
                self.writer["run_batch"]("unused", [0x3ff0000000000000], 1)

    def test_timeout_is_a_failure(self):
        with patch("subprocess.run", side_effect=subprocess.TimeoutExpired("unused", 1)), \
                self.assertRaises(self.writer["WriterScalarFailure"]):
            self.writer["run_batch"]("unused", [0x3ff0000000000000], 1)

    def test_integer_mode_checks_exact_signed_kind(self):
        self.writer["check_frame"](0x8000000000000000, b'T\t"v" = -9223372036854775808', True)
        self.writer["check_frame"](0x7fffffffffffffff, b'T\t"v" = 9223372036854775807', True)
        for frame in [b'T\t"v" = 1.0', b'T\t"v" = true', b'T\t"v" = 2']:
            with self.subTest(frame=frame), self.assertRaises(self.writer["WriterScalarFailure"]):
                self.writer["check_frame"](1, frame, True)


if __name__ == "__main__":
    unittest.main()
