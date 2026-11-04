# SPDX-License-Identifier: Apache-2.0
"""Regression checks for comparison framing and effective compiler provenance."""
import importlib.util
import unittest
from pathlib import Path
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("toml_comparison", Path(__file__).resolve().parents[1] / "scripts/compare.py")
comparison = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(comparison)


class ComparisonGuards(unittest.TestCase):
    def test_bad_frames(self):
        for value in ['{"a":1,"a":2}', '{"a":NaN}', '{"a":Infinity}',
                      '{"a":1e999}', '{} {}', '{"nested":{"a":1,"a":2}}']:
            with self.subTest(value=value), self.assertRaises(ValueError):
                comparison.strict_json(value)
        self.assertEqual(comparison.strict_json('{"a":1.25,"b":[true,"é"]}'), {"a": 1.25, "b": [True, "é"]})

    def test_decoded_types_are_distinct(self):
        self.assertFalse(comparison.typed_equal({"v": True}, {"v": 1}))
        self.assertFalse(comparison.typed_equal({"v": 1}, {"v": 1.0}))
        self.assertTrue(comparison.typed_equal({"v": [1, "é"]}, {"v": [1, "é"]}))

    def test_effective_rust_options(self):
        target = "x86_64-unknown-linux-gnu"
        command = ("rustc --crate-name goose_toml_compare --target " + target +
                   " -C opt-level=3 -C codegen-units=16 -C linker=cc")
        def verify(value):
            return comparison.verify_rust_commands("Running `" + value + "`")
        with patch.object(comparison, "rust_target", return_value=target):
            self.assertEqual(len(verify(command)), 1)
            self.assertEqual(len(verify("CARGO_PKG_VERSION=0.0.0 " + command)), 1)
            for value in [command + " -C target-cpu=native", command + " -C lto=thin",
                          command + " -C link-arg=-fuse-ld=mold", command + " -C incremental=cache",
                          command.replace("opt-level=3", "opt-level=1"), "sccache " + command]:
                with self.subTest(command=value), self.assertRaises(ValueError):
                    verify(value)


if __name__ == "__main__":
    unittest.main()
